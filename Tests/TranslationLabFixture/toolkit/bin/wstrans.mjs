#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const [command, projectPath, ...args] = process.argv.slice(2);
const projectJSON = path.join(projectPath ?? "", "project.json");
if (!command || !projectPath || !fs.existsSync(projectJSON)) {
  console.error("fixture toolkit requires a project command and project.json");
  process.exit(2);
}

const project = JSON.parse(fs.readFileSync(projectJSON, "utf8"));
const analysisDirectory = path.join(projectPath, "analysis");
const stageAuditPath = path.join(analysisDirectory, "fixture-stage-order.jsonl");
fs.mkdirSync(analysisDirectory, { recursive: true });
fs.appendFileSync(
  stageAuditPath,
  `${JSON.stringify({ command, args })}\n`,
);

if (command === "status") {
  const readiness = process.env.SWAN_SONG_FIXTURE_READINESS_STATUS ?? "COMPLETE";
  console.log(`Readiness: ${readiness} - ${project.game.title}`);
  console.log(`${readiness} Runtime Evidence: SwanSong fixture status override.`);
  process.exit(Number.parseInt(process.env.SWAN_SONG_FIXTURE_STATUS_EXIT_CODE ?? "0", 10));
}

if (command === "qa" || command === "validate") {
  const report = path.join(projectPath, "analysis", `fixture-${command}.json`);
  fs.mkdirSync(path.dirname(report), { recursive: true });
  fs.writeFileSync(report, `${JSON.stringify({ schema: "fixture-stage-v1", command, passed: true }, null, 2)}\n`);
  console.log(`PASS ${command}`);
  process.exit(0);
}

if (command === "pack") {
  if (args.length !== 2 || args[0] !== "--strict" || args[1] !== "true") {
    console.error("fixture pack requires exact --strict true arguments");
    process.exit(6);
  }
  const source = path.join(projectPath, project.rom.original);
  const target = path.join(projectPath, project.rom.patched);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(source, target);
  if (process.env.SWAN_SONG_FIXTURE_PATCH_COLOR_FLAG === "1") {
    const bytes = fs.readFileSync(target);
    bytes[bytes.length - 9] = 0x01;
    bytes[bytes.length - 2] = 0;
    bytes[bytes.length - 1] = 0;
    let checksum = 0;
    for (let index = 0; index < bytes.length - 2; index += 1) {
      checksum = (checksum + bytes[index]) & 0xffff;
    }
    bytes[bytes.length - 2] = checksum & 0xff;
    bytes[bytes.length - 1] = checksum >> 8;
    fs.writeFileSync(target, bytes);
  }
  const report = path.join(projectPath, "analysis", "fixture-strict-pack.json");
  fs.mkdirSync(path.dirname(report), { recursive: true });
  fs.writeFileSync(report, `${JSON.stringify({ schema: "fixture-stage-v1", command: "pack", strict: true }, null, 2)}\n`);
  console.log("PASS strict fixture pack");
  process.exit(0);
}

if (command === "capture-intake") {
  const option = (name) => {
    const index = args.indexOf(name);
    return index >= 0 ? args[index + 1] : undefined;
  };
  const ramPath = option("--ram");
  const name = option("--name");
  if (!ramPath || !name || !path.resolve(ramPath).startsWith(path.resolve(projectPath) + path.sep)) {
    console.error("unsafe fixture capture path");
    process.exit(3);
  }
  const bytes = fs.statSync(ramPath).size;
  if (bytes !== 16 * 1024 && bytes !== 64 * 1024) {
    console.error(`unexpected RAM size ${bytes}`);
    process.exit(4);
  }
  if (option("--authorized-exclusive-output") === "true") {
    const outputPath = option("--out");
    const receiptPath = option("--receipt");
    if (!outputPath || !receiptPath || path.dirname(outputPath) !== path.dirname(receiptPath)) {
      console.error("fixture authorized Capture Intake requires explicit sibling outputs");
      process.exit(7);
    }
    const ram = fs.readFileSync(ramPath);
    const sha256 = crypto.createHash("sha256").update(ram).digest("hex");
    fs.writeFileSync(outputPath, ram, { flag: "wx", mode: 0o600 });
    fs.chmodSync(outputPath, 0o600);
    const receipt = {
      kind: "capture-intake",
      version: 1,
      captureName: name,
      source: {
        kind: "raw-ram",
        path: path.relative(projectPath, ramPath),
        size: bytes,
        sha256,
      },
      output: {
        path: path.relative(projectPath, outputPath),
        size: bytes,
        sha256,
        copied: true,
        alreadyCurrent: false,
      },
      actualSize: bytes,
    };
    fs.writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, {
      flag: "wx",
      mode: 0o600,
    });
    fs.chmodSync(receiptPath, 0o600);
    console.log(`PASS capture intake ${name} (${bytes} bytes)`);
    process.exit(0);
  }
  const reportPath = path.join(projectPath, "analysis", `capture-intake-${name}.json`);
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify({ schema: "fixture-capture-intake-v1", name, bytes }, null, 2)}\n`);
  console.log(`PASS capture intake ${name} (${bytes} bytes)`);
  process.exit(0);
}

console.error(`fixture toolkit rejected command ${command}`);
process.exit(5);
