#!/usr/bin/env node

import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const FILE_MODE = 0o600;
const DIRECTORY_MODE = 0o700;
const PAYLOAD_ROLES = [
  "route",
  "original.frame", "original.state", "original.ram", "original.route",
  "original.intakeRam", "original.intakeReceipt", "original.manifest",
  "patched.frame", "patched.state", "patched.ram", "patched.route",
  "patched.intakeRam", "patched.intakeReceipt", "patched.manifest",
  "pair.plan", "pair.originalFrame", "pair.patchedFrame", "pair.pixelDiff",
  "pair.manifest",
];
const ROLE_SUFFIXES = [
  "route.json",
  "original/frame.png", "original/runtime.state", "original/ram.bin",
  "original/route.json", "original/capture-intake/capture.ram.bin",
  "original/capture-intake/receipt.json", "original/manifest.json",
  "patched/frame.png", "patched/runtime.state", "patched/ram.bin",
  "patched/route.json", "patched/capture-intake/capture.ram.bin",
  "patched/capture-intake/receipt.json", "patched/manifest.json",
  "pair/plan.json", "pair/original.png", "pair/patched.png",
  "pair/pixel-diff.json", "pair/manifest.json", "report.json",
];
const LEGACY_OFFICIAL_FULL_C_SHA256 =
  "5d55f817a0fbb321c35d5034e234d4ffe34603a7d9d587f4ccf2160d08b61c37";

function fail(message) {
  throw new Error(`authorized capture-plan KAT: ${message}`);
}

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function sortedJSONValue(value) {
  if (Array.isArray(value)) return value.map(sortedJSONValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort()
      .map((key) => [key, sortedJSONValue(value[key])]));
  }
  return value;
}

function canonicalJSON(value) {
  return JSON.stringify(sortedJSONValue(value));
}

function assertExactKeys(value, keys, label) {
  assert.equal(value && typeof value === "object" && !Array.isArray(value), true,
    `${label} is not an object`);
  assert.deepEqual(Object.keys(value).sort(), [...keys].sort(),
    `${label} fields are not exact`);
}

function pathSHA256(pathname) {
  return sha256(Buffer.from(pathname, "utf8"));
}

function artifact(pathname) {
  const bytes = fs.readFileSync(pathname);
  const stat = fs.statSync(pathname);
  return {
    byteCount: bytes.length,
    mode: stat.mode & 0o777,
    sha256: sha256(bytes),
  };
}

function identityOnly(pathname) {
  const value = artifact(pathname);
  return { byteCount: value.byteCount, sha256: value.sha256 };
}

function pngGeometry(pathname) {
  const bytes = fs.readFileSync(pathname);
  assert.equal(bytes.subarray(1, 4).toString("ascii"), "PNG");
  return {
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
  };
}

function makeDirectory(pathname) {
  fs.mkdirSync(pathname, { mode: DIRECTORY_MODE });
  fs.chmodSync(pathname, DIRECTORY_MODE);
}

function writePrivate(pathname, bytes) {
  fs.writeFileSync(pathname, bytes, { flag: "wx", mode: FILE_MODE });
  fs.chmodSync(pathname, FILE_MODE);
}

function requirePrivateRegularFile(pathname, label) {
  const stat = fs.lstatSync(pathname);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1
      || (stat.mode & 0o777) !== FILE_MODE || fs.realpathSync(pathname) !== pathname) {
    fail(`${label} is not one canonical 0600 single-link regular file`);
  }
  return artifact(pathname);
}

function writePrivateJSON(pathname, value) {
  writePrivate(pathname, Buffer.from(`${JSON.stringify(value, null, 2)}\n`, "utf8"));
}

function copyPrivate(source, destination) {
  fs.copyFileSync(source, destination, fs.constants.COPYFILE_EXCL);
  fs.chmodSync(destination, FILE_MODE);
}

function copyPrivateTree(source, destination) {
  makeDirectory(destination);
  for (const name of fs.readdirSync(source).sort()) {
    const sourcePath = path.join(source, name);
    const destinationPath = path.join(destination, name);
    const stat = fs.lstatSync(sourcePath);
    if (stat.isSymbolicLink()) fail(`toolkit source contains a link: ${sourcePath}`);
    if (stat.isDirectory()) {
      copyPrivateTree(sourcePath, destinationPath);
    } else if (stat.isFile()) {
      copyPrivate(sourcePath, destinationPath);
    } else {
      fail(`toolkit source contains an unsupported entry: ${sourcePath}`);
    }
  }
}

function run(runner, argumentsList, environment) {
  return spawnSync(runner, argumentsList, {
    env: environment,
    encoding: "utf8",
    maxBuffer: 8 * 1024 * 1024,
    timeout: 120_000,
  });
}

function requireSuccess(result, label) {
  if (result.error) fail(`${label} could not execute: ${result.error.message}`);
  if (result.signal) fail(`${label} terminated by ${result.signal}`);
  if (result.status !== 0) {
    fail(`${label} failed (${result.status}): ${String(result.stderr).slice(0, 1200)}`);
  }
}

function collectTree(root) {
  const records = [];
  function visit(directory, relativeRoot = "") {
    for (const name of fs.readdirSync(directory).sort()) {
      const pathname = path.join(directory, name);
      const relativePath = relativeRoot ? `${relativeRoot}/${name}` : name;
      const stat = fs.lstatSync(pathname, { bigint: true });
      if (stat.isSymbolicLink()) fail(`unexpected link in RUN: ${relativePath}`);
      if (stat.isDirectory()) {
        records.push({ relativePath, kind: "directory", mode: Number(stat.mode & 0o777n) });
        visit(pathname, relativePath);
      } else if (stat.isFile()) {
        records.push({
          relativePath,
          kind: "file",
          mode: Number(stat.mode & 0o777n),
          byteCount: Number(stat.size),
          sha256: sha256(fs.readFileSync(pathname)),
          ctimeNs: stat.ctimeNs,
        });
      } else {
        fail(`unsupported RUN entry: ${relativePath}`);
      }
    }
  }
  visit(root);
  return records;
}

function relativeInside(root, pathname, label) {
  const relativePath = path.relative(root, pathname).split(path.sep).join("/");
  if (!relativePath || relativePath.startsWith("../") || path.posix.isAbsolute(relativePath)) {
    fail(`${label} is outside the durable bundle`);
  }
  return relativePath;
}

function treeIdentity(root, { excluding = [] } = {}) {
  const excluded = new Set(excluding.map((pathname) => relativeInside(
    root, pathname, "excluded tree path",
  )));
  return collectTree(root).filter((record) => !excluded.has(record.relativePath))
    .map((record) => {
      if (record.kind === "directory") {
        return {
          relativePath: record.relativePath,
          kind: record.kind,
          mode: record.mode,
        };
      }
      return {
        relativePath: record.relativePath,
        kind: record.kind,
        mode: record.mode,
        byteCount: record.byteCount,
        sha256: record.sha256,
      };
    });
}

function treeSHA256(records) {
  return sha256(Buffer.from(canonicalJSON(records), "utf8"));
}

function fileBinding(pathname, label, { executable = false, mode } = {}) {
  const requested = path.resolve(pathname);
  const canonicalPath = fs.realpathSync(requested);
  const stat = fs.lstatSync(requested);
  const permissions = stat.mode & 0o777;
  if (canonicalPath !== requested || !stat.isFile() || stat.isSymbolicLink()
      || stat.nlink !== 1 || (mode !== undefined && permissions !== mode)
      || (executable && (permissions & 0o111) === 0)) {
    fail(`${label} is not one canonical bound regular file`);
  }
  return {
    canonicalPath,
    canonicalPathSHA256: pathSHA256(canonicalPath),
    artifact: artifact(canonicalPath),
  };
}

function validateFileBinding(binding, label, options = {}) {
  const current = fileBinding(binding.canonicalPath, label, options);
  assert.deepEqual(current, binding, `${label} binding drifted`);
  return current;
}

function plannedEntry(root, pathname, kind, mode) {
  return {
    relativePath: relativeInside(root, pathname, "planned output"),
    kind,
    mode,
  };
}

function plannedRunGraph({ root, projectRoot, nonceLedger, name, nonce, status }) {
  const runDirectory = path.join(projectRoot, "runs", name);
  const outputRoot = path.join(runDirectory, "outputs", nonce);
  const directories = [
    runDirectory,
    path.join(runDirectory, "outputs"),
    outputRoot,
    path.join(outputRoot, "original"),
    path.join(outputRoot, "original", "capture-intake"),
    path.join(outputRoot, "patched"),
    path.join(outputRoot, "patched", "capture-intake"),
    path.join(outputRoot, "pair"),
  ];
  const retainedSuffixes = status === "complete"
    ? ROLE_SUFFIXES
    : [...ROLE_SUFFIXES.slice(0, 8), ROLE_SUFFIXES.at(-1)];
  const files = [
    path.join(runDirectory, "authorization.json"),
    path.join(runDirectory, "closure.json"),
    ...retainedSuffixes.map((suffix) => path.join(outputRoot, suffix)),
    path.join(nonceLedger, `${nonce}.json`),
  ];
  return {
    status,
    nonce,
    nonceClaimPath: path.join(nonceLedger, `${nonce}.json`),
    runDirectory,
    authorizationPath: path.join(runDirectory, "authorization.json"),
    closurePath: path.join(runDirectory, "closure.json"),
    additions: [
      ...directories.map((pathname) => plannedEntry(root, pathname, "directory", DIRECTORY_MODE)),
      ...files.map((pathname) => plannedEntry(root, pathname, "file", FILE_MODE)),
    ].sort((left, right) => left.relativePath.localeCompare(right.relativePath)),
  };
}

function requireAbsent(paths, label) {
  for (const pathname of paths) {
    if (fs.existsSync(pathname)) fail(`${label} already exists: ${pathname}`);
  }
}

function exactTreeShape(records) {
  return records.map((record) => ({
    relativePath: record.relativePath,
    kind: record.kind,
    mode: record.mode,
  })).sort((left, right) => left.relativePath.localeCompare(right.relativePath));
}

function assertExactTreeShape(records, expected, label) {
  assert.deepEqual(exactTreeShape(records), [...expected].sort(
    (left, right) => left.relativePath.localeCompare(right.relativePath),
  ), label);
}

function assertTreeRecordsPreserved(currentRecords, retainedRecords, label) {
  const currentByPath = new Map(currentRecords.map((record) => [record.relativePath, record]));
  for (const retained of retainedRecords) {
    assert.deepEqual(currentByPath.get(retained.relativePath), retained,
      `${label}: ${retained.relativePath}`);
  }
}

function assertPrivateTree(records, label) {
  for (const record of records) {
    if (record.kind === "directory") {
      assert.equal(record.mode, DIRECTORY_MODE, `${label} directory is not 0700`);
    } else {
      assert.equal(record.mode === FILE_MODE || record.mode === DIRECTORY_MODE, true,
        `${label} file is not 0600 or an explicitly executable 0700 file`);
    }
  }
}

function expectedChildContract({ authorization, lane, toolkitRoot, projectRoot }) {
  const byRole = new Map(authorization.allowedOutputGraph.roles
    .map((record) => [record.role, record]));
  const source = byRole.get(`${lane}.ram`).canonicalDestination;
  const output = byRole.get(`${lane}.intakeRam`).canonicalDestination;
  const receipt = byRole.get(`${lane}.intakeReceipt`).canonicalDestination;
  const relative = (pathname) => path.relative(projectRoot, pathname).split(path.sep).join("/");
  const argumentsList = [
    path.join(toolkitRoot, "bin", "wstrans.mjs"),
    "capture-intake", projectRoot,
    "--ram", source,
    "--name", `authorized-${lane}`,
    "--expect-size", "auto",
    "--out", relative(output),
    "--receipt", relative(receipt),
    "--authorized-exclusive-output", "true",
    "--authorization-byte-count", String(artifact(path.join(authorization.runDirectory,
      "authorization.json")).byteCount),
    "--authorization-sha256", artifact(path.join(authorization.runDirectory,
      "authorization.json")).sha256,
    "--authorization-nonce", authorization.nonce,
    "--markdown", "false", "--analyze", "false", "--find-text", "false",
    "--triage", "false", "--render", "false",
  ];
  const environment = {
    LANG: "C",
    LC_ALL: "C",
    PATH: "/usr/bin:/bin",
    TZ: "UTC",
    WONDERSWAN_TOOLKIT_DIR: toolkitRoot,
  };
  return { argumentsList, environment };
}

function validateLaneWitness({ authorization, lane, toolkitRoot, projectRoot, nodePath }) {
  const role = authorization.allowedOutputGraph.roles
    .find((record) => record.role === `${lane}.manifest`);
  const manifest = JSON.parse(fs.readFileSync(role.canonicalDestination, "utf8"));
  const witness = manifest.captureIntakeExecution;
  const expected = expectedChildContract({ authorization, lane, toolkitRoot, projectRoot });
  assert.equal(witness.schema, "swan-song-authorized-capture-intake-execution-v1");
  assert.equal(witness.node.canonicalPath, nodePath);
  assert.deepEqual(witness.node.artifact, identityOnly(nodePath));
  assert.equal(witness.workingDirectory, toolkitRoot);
  assert.deepEqual(witness.arguments, expected.argumentsList);
  assert.equal(witness.argumentsSHA256,
    sha256(Buffer.from(canonicalJSON(expected.argumentsList), "utf8")));
  assert.deepEqual(witness.environment, expected.environment);
  assert.equal(witness.environmentSHA256,
    sha256(Buffer.from(canonicalJSON(expected.environment), "utf8")));
  assert.equal(witness.exitCode, 0);
  assert.deepEqual(witness.authorization, {
    nonce: authorization.nonce,
    artifact: identityOnly(path.join(authorization.runDirectory, "authorization.json")),
  });
}

function validateClosure({ authorization, expectedStatus, expectedPayloadRoles }) {
  const runDirectory = authorization.runDirectory;
  const closurePath = path.join(runDirectory, "closure.json");
  const reportRole = authorization.allowedOutputGraph.roles.at(-1);
  assert.equal(fs.existsSync(closurePath), true, "K must exist");
  const closure = JSON.parse(fs.readFileSync(closurePath, "utf8"));
  assert.equal(closure.schema, "swan-song-authorized-method-closure-v2");
  assert.equal(closure.method, "capture-plan");
  assert.equal(closure.status, expectedStatus);
  assert.equal(closure.nonce, authorization.nonce);
  assert.deepEqual(closure.authorization,
    identityOnly(path.join(runDirectory, "authorization.json")));
  for (const [key, requestKey] of [
    ["routeRunner", "routeRunner"],
    ["loadedDylib", "loadedDylib"],
  ]) {
    const executor = closure.executorAfter[key];
    const request = authorization.request[requestKey];
    assert.equal(executor.canonicalPath, request.canonicalPath);
    assert.deepEqual(executor.artifact, request.artifact);
    assert.equal(executor.mode, fs.statSync(request.canonicalPath).mode & 0o777);
  }
  assert.equal(closure.privateArtifacts.count, expectedPayloadRoles.length);
  assert.deepEqual(closure.privateArtifacts.records.map((record) => record.role),
    expectedPayloadRoles);
  assert.equal(closure.report.role, "report");
  assert.equal(closure.report.relativePath, reportRole.relativePath);
  const report = JSON.parse(fs.readFileSync(reportRole.canonicalDestination, "utf8"));
  assert.equal(report.schema, "swan-song-authorized-persisted-translation-capture-report-v2");
  assert.equal(report.status, expectedStatus);
  assert.deepEqual(report.authorization, {
    nonce: authorization.nonce,
    artifact: identityOnly(path.join(runDirectory, "authorization.json")),
  });

  const selected = new Set([...expectedPayloadRoles, "report"]);
  const expectedFiles = new Set(["authorization.json", "closure.json"]);
  for (const role of authorization.allowedOutputGraph.roles) {
    if (selected.has(role.role)) expectedFiles.add(role.relativePath);
  }
  const tree = collectTree(runDirectory);
  const actualFiles = tree.filter((record) => record.kind === "file")
    .map((record) => record.relativePath).sort();
  assert.deepEqual(actualFiles, [...expectedFiles].sort(), "RUN file graph must be exact");
  for (const record of tree) {
    assert.equal(record.mode, record.kind === "directory" ? DIRECTORY_MODE : FILE_MODE,
      `mode mismatch for ${record.relativePath}`);
  }
  for (const record of [...closure.privateArtifacts.records, closure.report]) {
    const role = authorization.allowedOutputGraph.roles
      .find((candidate) => candidate.role === record.role);
    assert.equal(record.byteCount, fs.statSync(role.canonicalDestination).size);
    assert.equal(record.sha256, sha256(fs.readFileSync(role.canonicalDestination)));
  }
  const closureCTime = tree.find((record) => record.relativePath === "closure.json").ctimeNs;
  for (const record of tree.filter((entry) => entry.kind === "file"
    && entry.relativePath !== "closure.json")) {
    assert.equal(closureCTime >= record.ctimeNs, true,
      `K was not created after ${record.relativePath}`);
  }
  return { closure, report, tree };
}

const repositoryRoot = fs.realpathSync(process.env.SWAN_CAPTURE_KAT_REPOSITORY ?? process.cwd());
const phase = process.env.SWAN_CAPTURE_KAT_PHASE;
if (phase !== "success" && phase !== "finalize") {
  fail("SWAN_CAPTURE_KAT_PHASE must be exactly success or finalize");
}
const toolkitSource = phase === "success"
  ? fs.realpathSync(process.env.SWAN_CAPTURE_AUTH_TOOLKIT_DIR
    ?? path.join(repositoryRoot, "..", "wonderswan-ai-translation-toolkit"))
  : null;
const runnerPath = fs.realpathSync(process.env.SWAN_CAPTURE_KAT_RUNNER
  ?? path.join(repositoryRoot, ".engine", "swift-capability-v5-live",
    "arm64-apple-macosx", "release", "SwanSongRouteRunner"));
const engineDirectory = fs.realpathSync(process.env.SWAN_ARES_ENGINE_DIR
  ?? path.join(repositoryRoot, ".engine", "build-capability-v4"));
const aresSourceRoot = fs.realpathSync(process.env.SWAN_CAPTURE_KAT_ARES_SOURCE
  ?? path.join(repositoryRoot, ".engine", "ares-capability-v4"));
const officialBaseCapabilityPath = phase === "success"
  ? fs.realpathSync(process.env.SWAN_CAPTURE_KAT_FULL_C
    ?? path.join(repositoryRoot, ".engine", "capability-c.vSIWur", "receipts",
      "full-c-v5.json"))
  : null;
const expectedFullC_SHA256 = process.env.SWAN_CAPTURE_KAT_FULL_C_SHA256
  ?? LEGACY_OFFICIAL_FULL_C_SHA256;
if (!/^[0-9a-f]{64}$/u.test(expectedFullC_SHA256)) {
  fail("SWAN_CAPTURE_KAT_FULL_C_SHA256 must be one lowercase SHA-256 digest");
}
const selectedEngineProfileName = process.env.SWAN_CAPTURE_KAT_ENGINE_PROFILE ?? "abi9";
if (!["abi9", "abi10", "abi10-capture"].includes(selectedEngineProfileName)) {
  fail("SWAN_CAPTURE_KAT_ENGINE_PROFILE is not one supported exact profile");
}
const authModulePath = phase === "success"
  ? path.join(toolkitSource, "lib", "swansong-capture-plan-authorization.mjs") : null;
const intakeModulePath = phase === "success"
  ? path.join(toolkitSource, "lib", "swansong-capture-intake-capability.mjs") : null;
const engineModulePath = phase === "success"
  ? path.join(toolkitSource, "lib", "swansong-engine-capability.mjs") : null;
const methodModulePath = phase === "success"
  ? path.join(toolkitSource, "lib", "swansong-capture-plan-method-capability.mjs") : null;
if (!process.env.SWAN_CAPTURE_KAT_BUNDLE) {
  fail("SWAN_CAPTURE_KAT_BUNDLE must name a caller-supplied durable bundle");
}
const durableBundle = path.resolve(process.env.SWAN_CAPTURE_KAT_BUNDLE);
const bundleStat = fs.lstatSync(durableBundle);
const temporaryRoot = fs.realpathSync(durableBundle);
if (temporaryRoot !== durableBundle || !bundleStat.isDirectory()
    || bundleStat.isSymbolicLink() || (bundleStat.mode & 0o777) !== DIRECTORY_MODE) {
  fail("durable bundle must be one caller-supplied canonical 0700 directory");
}
if (phase === "success" && fs.readdirSync(temporaryRoot).length !== 0) {
  fail("success phase requires a fresh empty durable bundle");
}
if (phase === "finalize" && fs.readdirSync(temporaryRoot).length === 0) {
  fail("finalize phase requires the retained success-phase bundle");
}

if (phase === "success") {
  const toolkitRoot = path.join(temporaryRoot, "toolkit");
  makeDirectory(toolkitRoot);
  for (const name of ["adapters", "bin", "lib", "scripts"]) {
    copyPrivateTree(path.join(toolkitSource, name), path.join(toolkitRoot, name));
  }
  copyPrivate(path.join(toolkitSource, "package.json"), path.join(toolkitRoot, "package.json"));

  const controlsDirectory = path.join(temporaryRoot, "controls");
  const nonceLedger = path.join(temporaryRoot, "nonce-ledger");
  makeDirectory(controlsDirectory);
  makeDirectory(nonceLedger);
  const nodePath = fs.realpathSync(process.execPath);
  const copiedAuthModulePath = path.join(toolkitRoot, path.relative(toolkitSource,
    authModulePath));
  const copiedIntakeModulePath = path.join(toolkitRoot, path.relative(toolkitSource,
    intakeModulePath));
  const copiedEngineModulePath = path.join(toolkitRoot, path.relative(toolkitSource,
    engineModulePath));
  const copiedMethodModulePath = path.join(toolkitRoot, path.relative(toolkitSource,
    methodModulePath));
  const runnerLauncherPath = path.join(toolkitRoot, "scripts",
    "run-swansong-authorized-capture-plan.mjs");
  const overBoundHelperPath = path.join(toolkitRoot, "scripts",
    "run-swansong-capture-plan-over-bound-control.mjs");
  fs.chmodSync(runnerLauncherPath, DIRECTORY_MODE);
  fs.chmodSync(overBoundHelperPath, DIRECTORY_MODE);
  const authModule = await import(pathToFileURL(copiedAuthModulePath));
  const intakeModule = await import(pathToFileURL(copiedIntakeModulePath));
  const engineModule = await import(pathToFileURL(copiedEngineModulePath));
  const methodModule = await import(pathToFileURL(copiedMethodModulePath));
  const officialBaseBytes = fs.readFileSync(officialBaseCapabilityPath);
  assert.equal(sha256(officialBaseBytes), expectedFullC_SHA256,
    "the official full-C receipt digest must be exact");
  assert.equal(requirePrivateRegularFile(officialBaseCapabilityPath,
    "external official full C").sha256, expectedFullC_SHA256);
  const officialBaseCapability = JSON.parse(officialBaseBytes);
  const engineProfile = new Map([
    ["abi9", engineModule.SWANSONG_ENGINE_PROFILE_ABI9],
    ["abi10", engineModule.SWANSONG_ENGINE_PROFILE_ABI10],
    ["abi10-capture", engineModule.SWANSONG_ENGINE_PROFILE_ABI10_CAPTURE],
  ]).get(selectedEngineProfileName);
  if (!engineProfile) fail("selected engine profile is unavailable in the copied toolkit");
  const engineCapabilityOptions = {
    swanSongRoot: repositoryRoot,
    aresSourceRoot,
    engineDirectory,
    routeRunner: runnerPath,
    engineProfile,
  };
  const preM0Current = engineModule.collectSwanSongEngineCapability(engineCapabilityOptions);
  engineModule.validateSwanSongEngineCapabilityReceipt(officialBaseCapability, preM0Current);
  const preM0Bytes = Buffer.from(`${JSON.stringify(preM0Current, null, 2)}\n`, "utf8");
  assert.deepEqual(preM0Bytes, officialBaseBytes,
    "fresh pre-M0 full C must equal the official receipt byte-for-byte");
  const baseCapabilityPath = path.join(controlsDirectory, "full-c.json");
  writePrivate(baseCapabilityPath, officialBaseBytes);
  const localBaseArtifact = requirePrivateRegularFile(baseCapabilityPath,
    "bundle-local full C");
  assert.equal(localBaseArtifact.sha256, expectedFullC_SHA256);
  assert.deepEqual(fs.readFileSync(baseCapabilityPath), officialBaseBytes,
    "bundle-local full C must be the exact raw official bytes");
  const baseCapability = JSON.parse(fs.readFileSync(baseCapabilityPath));
  engineModule.validateSwanSongEngineCapabilityReceipt(baseCapability, preM0Current);
  const loadedDylibPath = fs.realpathSync(preM0Current.engine.loadedDylibPath);

  const fixtureRoot = path.join(temporaryRoot, "capture-intake-fixture");
  const intakeCapability = intakeModule.collectSwanSongCaptureIntakeCapability({
    toolkitRoot,
    nodeExecutable: nodePath,
    fixtureRoot,
  });
  const intakeCapabilityPath = path.join(controlsDirectory, "capture-intake-capability.json");
  writePrivateJSON(intakeCapabilityPath, intakeCapability);
  intakeModule.validateSwanSongCaptureIntakeCapabilityReceipt(intakeCapability, {
    toolkitRoot,
    nodeExecutable: nodePath,
    fixtureRoot,
  });
  const bootstrapPath = path.join(controlsDirectory, "capture-plan-bootstrap.json");
  authModule.createSwanSongCapturePlanBootstrapCapability({
    baseCapabilityReceiptPath: baseCapabilityPath,
    captureIntakeCapabilityReceiptPath: intakeCapabilityPath,
    toolkitRoot,
    nodeExecutable: nodePath,
    captureIntakeFixtureRoot: fixtureRoot,
    outputPath: bootstrapPath,
  });
  authModule.validateSwanSongCapturePlanBootstrapCapability({
    baseCapabilityReceiptPath: baseCapabilityPath,
    captureIntakeCapabilityReceiptPath: intakeCapabilityPath,
    bootstrapCapabilityPath: bootstrapPath,
    toolkitRoot,
    nodeExecutable: nodePath,
    captureIntakeFixtureRoot: fixtureRoot,
  });
  const postM0Current = engineModule.collectSwanSongEngineCapability(engineCapabilityOptions);
  engineModule.validateSwanSongEngineCapabilityReceipt(baseCapability, postM0Current);
  const postM0Bytes = Buffer.from(`${JSON.stringify(postM0Current, null, 2)}\n`, "utf8");
  assert.deepEqual(postM0Bytes, fs.readFileSync(baseCapabilityPath),
    "fresh post-M0 full C must equal the bundle-local receipt byte-for-byte");
  assert.equal(requirePrivateRegularFile(baseCapabilityPath,
    "post-M0 bundle-local full C").sha256, expectedFullC_SHA256);
  intakeModule.validateSwanSongCaptureIntakeCapabilityReceipt(intakeCapability, {
    toolkitRoot,
    nodeExecutable: nodePath,
    fixtureRoot,
  });

  const projectsDirectory = path.join(toolkitRoot, "projects");
  const projectRoot = path.join(projectsDirectory, "public-capture-kat");
  makeDirectory(projectsDirectory);
  makeDirectory(projectRoot);
  for (const relativePath of ["rom", "build", "plans", "runs"]) {
    makeDirectory(path.join(projectRoot, relativePath));
  }
  copyPrivate(path.join(repositoryRoot, "Tests", "TranslationLabFixture", "project.json"),
    path.join(projectRoot, "project.json"));
  copyPrivate(path.join(repositoryRoot, "Tests", "TranslationLabFixture", "capture-plan.json"),
    path.join(projectRoot, "plans", "capture-plan.json"));
  const publicROM = path.join(repositoryRoot, "testroms", "ws-test-suite", "80186_quirks",
    "80186_quirks.ws");
  copyPrivate(publicROM, path.join(projectRoot, "rom", "original.ws"));
  copyPrivate(publicROM, path.join(projectRoot, "build", "patched.ws"));
  const planPath = path.join(projectRoot, "plans", "capture-plan.json");
  if (typeof process.getuid !== "function") {
    fail("the macOS capture-plan environment requires an execution UID");
  }
  const cfUserTextEncoding = `0x${process.getuid().toString(16).toUpperCase()}:0x0:0x0`;
  const runnerEnvironment = Object.freeze({
    LANG: "C",
    LC_ALL: "C",
    PATH: "/usr/bin:/bin",
    SWAN_ARES_ENGINE_DIR: engineDirectory,
    TZ: "UTC",
    __CF_USER_TEXT_ENCODING: cfUserTextEncoding,
  });
  assert.deepEqual(Object.keys(runnerEnvironment).sort(), [
    "LANG", "LC_ALL", "PATH", "SWAN_ARES_ENGINE_DIR", "TZ",
    "__CF_USER_TEXT_ENCODING",
  ]);
  assert.equal(runnerEnvironment.SWAN_ARES_ENGINE_DIR, fs.realpathSync(engineDirectory));

  const issuedNonces = new Set();
  function freshNonce() {
    let nonce;
    do nonce = crypto.randomBytes(32).toString("hex");
    while (issuedNonces.has(nonce));
    issuedNonces.add(nonce);
    assert.equal(fs.existsSync(path.join(nonceLedger, `${nonce}.json`)), false);
    return nonce;
  }

  function issueAuthorization({ name, nonce, faultInjection = null, selectedPlan = planPath }) {
    const runDirectory = path.join(projectRoot, "runs", name);
    if (fs.existsSync(runDirectory)) fail(`run directory ${name} is not fresh`);
    return authModule.createSwanSongCapturePlanAuthorization({
      baseCapabilityReceiptPath: baseCapabilityPath,
      captureIntakeCapabilityReceiptPath: intakeCapabilityPath,
      bootstrapCapabilityPath: bootstrapPath,
      toolkitRoot,
      nodeExecutable: nodePath,
      runnerLauncherPath,
      captureIntakeFixtureRoot: fixtureRoot,
      nonceLedgerDirectory: nonceLedger,
      nonce,
      runDirectory,
      projectRoot,
      projectManifestPath: path.join(projectRoot, "project.json"),
      planPath: selectedPlan,
      originalROMPath: path.join(projectRoot, "rom", "original.ws"),
      patchedROMPath: path.join(projectRoot, "build", "patched.ws"),
      routeRunnerPath: runnerPath,
      loadedDylibPath,
      faultInjection,
    });
  }

  function launchAuthorized(authorization) {
    return run(nodePath, [
      runnerLauncherPath, "--authorization", authorization.path,
    ], runnerEnvironment);
  }

  const successNonce = freshNonce();
  const blockedNonce = freshNonce();
  const overBoundNonce = freshNonce();
  assert.equal(new Set([successNonce, blockedNonce, overBoundNonce]).size, 3);

  const overBoundPlan = path.join(projectRoot, "plans", "over-bound.json");
  writePrivateJSON(overBoundPlan, {
    schema: "swan-song-frame-input-plan-v1",
    totalFrames: 1_000_001,
    events: [{ frameIndex: 0, inputs: [] }],
  });
  const publicPlan = JSON.parse(fs.readFileSync(planPath, "utf8"));
  assert.equal(publicPlan.schema, "swan-song-frame-input-plan-v1");
  assert.equal(publicPlan.totalFrames, 30,
    "the coordinator must retain the pinned 30-frame capture-plan fixture");

  const coordinatorManifestPath = path.join(temporaryRoot, "coordinator-manifest.json");
  const successPhaseReceiptPath = path.join(temporaryRoot, "success-phase-receipt.json");
  const finalBundleManifestPath = path.join(temporaryRoot, "bundle-manifest.json");
  const overBoundRunDirectory = path.join(projectRoot, "runs", "over-bound");
  const overBoundRequestPath = path.join(controlsDirectory, "over-bound.request.json");
  const overBoundPreclaimPath = path.join(controlsDirectory, "over-bound.preclaim.json");
  const overBoundReceiptPath = path.join(controlsDirectory, "over-bound.receipt.json");
  const methodCapabilityPath = path.join(controlsDirectory,
    "capture-plan-method-capability.json");
  const successGraph = plannedRunGraph({
    root: temporaryRoot, projectRoot, nonceLedger, name: "success",
    nonce: successNonce, status: "complete",
  });
  const blockedGraph = plannedRunGraph({
    root: temporaryRoot, projectRoot, nonceLedger, name: "blocked",
    nonce: blockedNonce, status: "blocked",
  });
  const successAdditions = [
    plannedEntry(temporaryRoot, coordinatorManifestPath, "file", FILE_MODE),
    ...successGraph.additions,
    plannedEntry(temporaryRoot, successPhaseReceiptPath, "file", FILE_MODE),
  ].sort((left, right) => left.relativePath.localeCompare(right.relativePath));
  const finalizeAdditions = [
    ...blockedGraph.additions,
    plannedEntry(temporaryRoot, overBoundRequestPath, "file", FILE_MODE),
    plannedEntry(temporaryRoot, overBoundPreclaimPath, "file", FILE_MODE),
    plannedEntry(temporaryRoot, overBoundReceiptPath, "file", FILE_MODE),
    plannedEntry(temporaryRoot, methodCapabilityPath, "file", FILE_MODE),
    plannedEntry(temporaryRoot, finalBundleManifestPath, "file", FILE_MODE),
  ].sort((left, right) => left.relativePath.localeCompare(right.relativePath));
  const plannedRelativePaths = [...successAdditions, ...finalizeAdditions]
    .map((entry) => entry.relativePath);
  assert.equal(new Set(plannedRelativePaths).size, plannedRelativePaths.length,
    "two-phase output additions must be disjoint");

  const plannedDestinationPaths = [...successAdditions, ...finalizeAdditions]
    .map((entry) => path.join(temporaryRoot, ...entry.relativePath.split("/")));
  const overBoundNonceClaimPath = path.join(nonceLedger, `${overBoundNonce}.json`);
  requireAbsent([
    ...plannedDestinationPaths,
    overBoundRunDirectory,
    path.join(overBoundRunDirectory, "authorization.json"),
    path.join(overBoundRunDirectory, "closure.json"),
    overBoundNonceClaimPath,
  ], "pre-manifest planned destination");

  const qualificationSourceClosure =
    methodModule.collectSwanSongCapturePlanQualificationSourceClosure({
      toolkitRoot,
      helperPath: overBoundHelperPath,
      launcherPath: runnerLauncherPath,
    });
  const preparedTree = treeIdentity(temporaryRoot);
  assertPrivateTree(preparedTree, "prepared bundle");
  const coordinatorScriptPath = fs.realpathSync(fileURLToPath(import.meta.url));
  const coordinatorManifest = {
    schema: "swan-song-authorized-capture-plan-kat-coordinator-v1",
    phaseModel: ["success", "finalize"],
    publicFixtureOnly: true,
    diagnosticOnly: true,
    commercialExecutionAuthorized: false,
    promotionEligible: false,
    durableBundle: {
      canonicalPath: temporaryRoot,
      canonicalPathSHA256: pathSHA256(temporaryRoot),
      mode: DIRECTORY_MODE,
    },
    coordinator: fileBinding(coordinatorScriptPath, "KAT coordinator", {
      executable: true,
    }),
    fullCapability: {
      officialReceiptSHA256: expectedFullC_SHA256,
      engineProfileID: engineProfile.id,
      localReceipt: fileBinding(baseCapabilityPath, "bundle-local full C", {
        mode: FILE_MODE,
      }),
      localReceiptIsSoleDownstreamBasePath: true,
      refreshedSourceState: preM0Current.sourceState,
      validatedExternalBeforeExclusiveCopy: true,
      validatedLocalBeforeAndAfterIntakeAndM0: true,
    },
    captureIntakeCapability: fileBinding(intakeCapabilityPath,
      "Capture Intake capability", { mode: FILE_MODE }),
    bootstrapCapability: fileBinding(bootstrapPath, "capture-plan M0", {
      mode: FILE_MODE,
    }),
    engine: {
      routeRunner: fileBinding(runnerPath, "route runner", { executable: true }),
      loadedDylib: fileBinding(loadedDylibPath, "loaded engine dylib"),
      sourceState: preM0Current.sourceState,
    },
    processExecution: {
      node: fileBinding(nodePath, "explicit Node executable", { executable: true }),
      launcher: fileBinding(runnerLauncherPath, "capture-plan launcher", {
        executable: true,
        mode: DIRECTORY_MODE,
      }),
      environment: runnerEnvironment,
      environmentSHA256: sha256(Buffer.from(canonicalJSON(runnerEnvironment), "utf8")),
    },
    qualificationSourceClosure,
    publicFixture: {
      projectRoot,
      projectManifest: fileBinding(path.join(projectRoot, "project.json"),
        "public project manifest", { mode: FILE_MODE }),
      plan: {
        ...fileBinding(planPath, "public 30-frame plan", { mode: FILE_MODE }),
        totalFrames: 30,
      },
      originalROM: fileBinding(path.join(projectRoot, "rom", "original.ws"),
        "public Original ROM", { mode: FILE_MODE }),
      patchedROM: fileBinding(path.join(projectRoot, "build", "patched.ws"),
        "public Patched ROM", { mode: FILE_MODE }),
      sameROMRequired: true,
    },
    planned: {
      nonces: { success: successNonce, blocked: blockedNonce, overBound: overBoundNonce },
      success: successGraph,
      blocked: blockedGraph,
      overBound: {
        nonce: overBoundNonce,
        nonceClaimPath: overBoundNonceClaimPath,
        runDirectory: overBoundRunDirectory,
        requestPath: overBoundRequestPath,
        preclaimPath: overBoundPreclaimPath,
        receiptPath: overBoundReceiptPath,
      },
      successPhaseReceiptPath,
      methodCapabilityPath,
      finalBundleManifestPath,
    },
    allowedTwoPhaseAdditions: {
      success: successAdditions,
      finalize: finalizeAdditions,
      overBoundRunDirectoryMustRemainAbsent: true,
      overBoundNonceClaimMustRemainAbsent: true,
      extraOutputRuntimeAllowed: false,
      crossMethodRuntimeAllowed: false,
    },
    preparedTree,
    preparedTreeSHA256: treeSHA256(preparedTree),
  };
  writePrivateJSON(coordinatorManifestPath, coordinatorManifest);
  assert.deepEqual(JSON.parse(fs.readFileSync(coordinatorManifestPath, "utf8")),
    coordinatorManifest, "coordinator manifest changed after exclusive creation");

  const success = issueAuthorization({ name: "success", nonce: successNonce });
  const successResult = launchAuthorized(success);
  requireSuccess(successResult, "authorized success control");
  const retainedSuccess = methodModule.verifyRetainedSwanSongCapturePlanControl({
    authorizationPath: success.path,
    baseCapabilityReceiptPath: baseCapabilityPath,
    captureIntakeCapabilityReceiptPath: intakeCapabilityPath,
    bootstrapCapabilityPath: bootstrapPath,
    expectedStatus: "complete",
  });
  const successProof = validateClosure({
    authorization: success.authorization,
    expectedStatus: "complete",
    expectedPayloadRoles: PAYLOAD_ROLES,
  });
  assert.equal(successProof.report.payloadArtifactCount, 20);
  assert.equal(successProof.report.differentPixelCount, 0);
  assert.equal(successProof.report.differentPixelFraction, 0);
  const successRoles = new Map(success.authorization.allowedOutputGraph.roles
    .map((record) => [record.role, record]));
  const originalFramePath = successRoles.get("original.frame").canonicalDestination;
  const patchedFramePath = successRoles.get("patched.frame").canonicalDestination;
  const nativeGeometry = pngGeometry(originalFramePath);
  assert.deepEqual(nativeGeometry, pngGeometry(patchedFramePath));
  assert.equal(nativeGeometry.width > 0 && nativeGeometry.height > 0, true);
  assert.deepEqual(identityOnly(originalFramePath), identityOnly(patchedFramePath));
  const originalManifest = JSON.parse(fs.readFileSync(
    successRoles.get("original.manifest").canonicalDestination, "utf8"));
  const patchedManifest = JSON.parse(fs.readFileSync(
    successRoles.get("patched.manifest").canonicalDestination, "utf8"));
  assert.equal(originalManifest.nativeFrameSHA256, patchedManifest.nativeFrameSHA256);
  const pixelDiff = JSON.parse(fs.readFileSync(
    successRoles.get("pair.pixelDiff").canonicalDestination, "utf8"));
  assert.equal(pixelDiff.width > 0 && pixelDiff.width <= nativeGeometry.width, true);
  assert.equal(pixelDiff.height > 0 && pixelDiff.height <= nativeGeometry.height, true);
  assert.equal(pixelDiff.difference.differentPixelCount, 0);
  assert.equal(pixelDiff.differentPixelFraction, 0);
  assert.equal(pixelDiff.changedBounds ?? null, null);
  validateLaneWitness({ authorization: success.authorization, lane: "original",
    toolkitRoot, projectRoot, nodePath });
  validateLaneWitness({ authorization: success.authorization, lane: "patched",
    toolkitRoot, projectRoot, nodePath });

  const phaseOneTreeBeforeReceipt = treeIdentity(temporaryRoot);
  const expectedPhaseOneBeforeReceipt = [
    ...exactTreeShape(preparedTree),
    ...successAdditions.filter((entry) =>
      entry.relativePath !== relativeInside(temporaryRoot, successPhaseReceiptPath,
        "success receipt")),
  ];
  assertExactTreeShape(phaseOneTreeBeforeReceipt, expectedPhaseOneBeforeReceipt,
    "success phase wrote outside its complete planned graph");
  assertTreeRecordsPreserved(phaseOneTreeBeforeReceipt, preparedTree,
    "success phase changed a prepared input");
  assertPrivateTree(phaseOneTreeBeforeReceipt, "success-phase retained tree");
  requireAbsent(finalizeAdditions.map((entry) =>
    path.join(temporaryRoot, ...entry.relativePath.split("/"))),
  "finalize-phase destination during success");
  requireAbsent([overBoundRunDirectory, overBoundNonceClaimPath],
    "over-bound target during success");

  const successPhaseReceipt = {
    schema: "swan-song-authorized-capture-plan-kat-success-phase-v1",
    phase: "success",
    coordinatorManifest: fileBinding(coordinatorManifestPath, "coordinator manifest", {
      mode: FILE_MODE,
    }),
    success: {
      authorization: fileBinding(success.path, "success authorization", {
        mode: FILE_MODE,
      }),
      closure: fileBinding(path.join(success.runDirectory, "closure.json"),
        "success closure", { mode: FILE_MODE }),
      report: fileBinding(success.authorization.allowedOutputGraph.roles.at(-1)
        .canonicalDestination, "success report", { mode: FILE_MODE }),
      retainedControl: retainedSuccess,
      payloadArtifactCount: successProof.closure.privateArtifacts.count,
      sameROMNativeZeroDiff: true,
      exactPlanFrames: 30,
      executionCount: 1,
    },
    phaseOneTreeBeforeReceipt,
    phaseOneTreeBeforeReceiptSHA256: treeSHA256(phaseOneTreeBeforeReceipt),
    finalizeDestinationsAbsent: true,
    overBoundRunAndNonceClaimAbsent: true,
    noBlockedExecution: true,
    noExtraOutputExecution: true,
    noCrossMethodExecution: true,
    noOverBoundExecution: true,
    noMethodCapability: true,
  };
  writePrivateJSON(successPhaseReceiptPath, successPhaseReceipt);
  const completedPhaseOneTree = treeIdentity(temporaryRoot);
  assertExactTreeShape(completedPhaseOneTree, [
    ...exactTreeShape(preparedTree), ...successAdditions,
  ], "completed success phase differs from the coordinator output graph");
  assertTreeRecordsPreserved(completedPhaseOneTree, phaseOneTreeBeforeReceipt,
    "success receipt creation changed retained phase-one evidence");
  assertPrivateTree(completedPhaseOneTree, "completed success-phase tree");

  process.stdout.write(`${JSON.stringify({
    schema: "swan-song-authorized-capture-plan-kat-phase-summary-v1",
    status: "success-phase-complete",
    nextPhase: "finalize",
    publicFixtureOnly: true,
    exactPlanFrames: 30,
    successExecutionCount: 1,
    successPayloadCount: successProof.closure.privateArtifacts.count,
    sameROMNativeZeroDiff: true,
    fullCapabilitySHA256: expectedFullC_SHA256,
    coordinatorManifestSHA256: identityOnly(coordinatorManifestPath).sha256,
    successPhaseReceiptSHA256: identityOnly(successPhaseReceiptPath).sha256,
    durableBundle: temporaryRoot,
    commercialExecutionAuthorized: false,
    promotionEligible: false,
  }, null, 2)}\n`);
} else {
  const toolkitRoot = path.join(temporaryRoot, "toolkit");
  const controlsDirectory = path.join(temporaryRoot, "controls");
  const nonceLedger = path.join(temporaryRoot, "nonce-ledger");
  const projectRoot = path.join(toolkitRoot, "projects", "public-capture-kat");
  const fixtureRoot = path.join(temporaryRoot, "capture-intake-fixture");
  const baseCapabilityPath = path.join(controlsDirectory, "full-c.json");
  const intakeCapabilityPath = path.join(controlsDirectory,
    "capture-intake-capability.json");
  const bootstrapPath = path.join(controlsDirectory, "capture-plan-bootstrap.json");
  const coordinatorManifestPath = path.join(temporaryRoot, "coordinator-manifest.json");
  const successPhaseReceiptPath = path.join(temporaryRoot, "success-phase-receipt.json");
  const finalBundleManifestPath = path.join(temporaryRoot, "bundle-manifest.json");
  const planPath = path.join(projectRoot, "plans", "capture-plan.json");
  const overBoundPlan = path.join(projectRoot, "plans", "over-bound.json");
  const nodePath = fs.realpathSync(process.execPath);
  const copiedAuthModulePath = path.join(toolkitRoot,
    "lib", "swansong-capture-plan-authorization.mjs");
  const copiedIntakeModulePath = path.join(toolkitRoot,
    "lib", "swansong-capture-intake-capability.mjs");
  const copiedEngineModulePath = path.join(toolkitRoot,
    "lib", "swansong-engine-capability.mjs");
  const copiedMethodModulePath = path.join(toolkitRoot,
    "lib", "swansong-capture-plan-method-capability.mjs");
  const runnerLauncherPath = path.join(toolkitRoot, "scripts",
    "run-swansong-authorized-capture-plan.mjs");
  const overBoundHelperPath = path.join(toolkitRoot, "scripts",
    "run-swansong-capture-plan-over-bound-control.mjs");
  const trustedSuccessReceiptSHA256 = process.env.SWAN_CAPTURE_KAT_SUCCESS_RECEIPT_SHA256;
  assert.match(trustedSuccessReceiptSHA256 ?? "", /^[0-9a-f]{64}$/u,
    "finalize requires the success receipt digest returned by the success phase");
  const successPhaseReceiptFile = requirePrivateRegularFile(successPhaseReceiptPath,
    "success-phase receipt");
  assert.equal(successPhaseReceiptFile.sha256, trustedSuccessReceiptSHA256,
    "success-phase receipt does not match the caller-retained digest");
  const successPhaseReceipt = JSON.parse(fs.readFileSync(successPhaseReceiptPath, "utf8"));
  assert.equal(successPhaseReceipt.schema,
    "swan-song-authorized-capture-plan-kat-success-phase-v1");
  assert.equal(successPhaseReceipt.phase, "success");
  assert.equal(successPhaseReceipt.phaseOneTreeBeforeReceiptSHA256,
    treeSHA256(successPhaseReceipt.phaseOneTreeBeforeReceipt));
  const coordinatorManifestFile = requirePrivateRegularFile(coordinatorManifestPath,
    "coordinator manifest");
  assert.deepEqual(successPhaseReceipt.coordinatorManifest,
    fileBinding(coordinatorManifestPath, "coordinator manifest", { mode: FILE_MODE }));
  assert.deepEqual(successPhaseReceipt.coordinatorManifest.artifact,
    coordinatorManifestFile);
  const retainedBeforeReceipt = treeIdentity(temporaryRoot, {
    excluding: [successPhaseReceiptPath],
  });
  assert.deepEqual(retainedBeforeReceipt, successPhaseReceipt.phaseOneTreeBeforeReceipt,
    "retained phase-one bytes changed before finalize");

  const coordinatorManifest = JSON.parse(fs.readFileSync(coordinatorManifestPath, "utf8"));
  assert.equal(coordinatorManifest.schema,
    "swan-song-authorized-capture-plan-kat-coordinator-v1");
  assert.deepEqual(coordinatorManifest.phaseModel, ["success", "finalize"]);
  assert.equal(coordinatorManifest.durableBundle.canonicalPath, temporaryRoot);
  assert.equal(coordinatorManifest.durableBundle.canonicalPathSHA256,
    pathSHA256(temporaryRoot));
  assert.equal(coordinatorManifest.durableBundle.mode, DIRECTORY_MODE);
  assert.equal(coordinatorManifest.publicFixtureOnly, true);
  assert.equal(coordinatorManifest.commercialExecutionAuthorized, false);
  assert.equal(coordinatorManifest.promotionEligible, false);
  assert.equal(coordinatorManifest.preparedTreeSHA256,
    treeSHA256(coordinatorManifest.preparedTree));
  assertPrivateTree(coordinatorManifest.preparedTree, "manifest prepared tree");

  const coordinatorScriptPath = fs.realpathSync(fileURLToPath(import.meta.url));
  assert.deepEqual(coordinatorManifest.coordinator,
    fileBinding(coordinatorScriptPath, "KAT coordinator", { executable: true }));
  assert.equal(coordinatorManifest.engine.routeRunner.canonicalPath, runnerPath,
    "finalize runner path differs from the phase-one binding");

  // The retained phase-one receipt is authenticated before any copied JavaScript executes.
  const authModule = await import(pathToFileURL(copiedAuthModulePath));
  const intakeModule = await import(pathToFileURL(copiedIntakeModulePath));
  const engineModule = await import(pathToFileURL(copiedEngineModulePath));
  const methodModule = await import(pathToFileURL(copiedMethodModulePath));
  assert.equal(coordinatorManifest.fullCapability.officialReceiptSHA256,
    expectedFullC_SHA256);
  assert.equal(coordinatorManifest.fullCapability.localReceiptIsSoleDownstreamBasePath, true);
  validateFileBinding(coordinatorManifest.fullCapability.localReceipt,
    "bundle-local full C", { mode: FILE_MODE });
  assert.equal(coordinatorManifest.fullCapability.localReceipt.canonicalPath,
    baseCapabilityPath);
  assert.equal(coordinatorManifest.fullCapability.localReceipt.artifact.sha256,
    expectedFullC_SHA256);
  validateFileBinding(coordinatorManifest.captureIntakeCapability,
    "Capture Intake capability", { mode: FILE_MODE });
  validateFileBinding(coordinatorManifest.bootstrapCapability,
    "capture-plan M0", { mode: FILE_MODE });
  validateFileBinding(coordinatorManifest.engine.routeRunner, "route runner", {
    executable: true,
  });
  validateFileBinding(coordinatorManifest.engine.loadedDylib, "loaded engine dylib");
  validateFileBinding(coordinatorManifest.processExecution.node,
    "explicit Node executable", { executable: true });
  validateFileBinding(coordinatorManifest.processExecution.launcher,
    "capture-plan launcher", { executable: true, mode: DIRECTORY_MODE });
  assert.equal(coordinatorManifest.processExecution.node.canonicalPath, nodePath);
  assert.equal(coordinatorManifest.processExecution.launcher.canonicalPath,
    runnerLauncherPath);
  assert.equal(typeof process.getuid, "function");
  const runnerEnvironment = Object.freeze({
    LANG: "C",
    LC_ALL: "C",
    PATH: "/usr/bin:/bin",
    SWAN_ARES_ENGINE_DIR: engineDirectory,
    TZ: "UTC",
    __CF_USER_TEXT_ENCODING:
      `0x${process.getuid().toString(16).toUpperCase()}:0x0:0x0`,
  });
  assert.deepEqual(Object.keys(runnerEnvironment).sort(), [
    "LANG", "LC_ALL", "PATH", "SWAN_ARES_ENGINE_DIR", "TZ",
    "__CF_USER_TEXT_ENCODING",
  ]);
  assert.deepEqual(coordinatorManifest.processExecution.environment, runnerEnvironment);
  assert.equal(coordinatorManifest.processExecution.environmentSHA256,
    sha256(Buffer.from(canonicalJSON(runnerEnvironment), "utf8")));

  methodModule.validateSwanSongCapturePlanQualificationSourceClosure(
    coordinatorManifest.qualificationSourceClosure,
    { toolkitRoot, helperPath: overBoundHelperPath, launcherPath: runnerLauncherPath },
  );
  const baseCapability = JSON.parse(fs.readFileSync(baseCapabilityPath, "utf8"));
  const retainedEngineProfile = new Map([
    ["swan-song-engine-profile-abi9-v1", engineModule.SWANSONG_ENGINE_PROFILE_ABI9],
    ["swan-song-engine-profile-abi10-v3", engineModule.SWANSONG_ENGINE_PROFILE_ABI10],
    ["swan-song-engine-profile-abi10-capture-v1",
      engineModule.SWANSONG_ENGINE_PROFILE_ABI10_CAPTURE],
  ]).get(coordinatorManifest.fullCapability.engineProfileID);
  if (!retainedEngineProfile) fail("retained engine profile is unavailable");
  const engineCapabilityOptions = {
    swanSongRoot: repositoryRoot,
    aresSourceRoot,
    engineDirectory,
    routeRunner: runnerPath,
    engineProfile: retainedEngineProfile,
  };
  const currentEngineCapability =
    engineModule.collectSwanSongEngineCapability(engineCapabilityOptions);
  engineModule.validateSwanSongEngineCapabilityReceipt(baseCapability,
    currentEngineCapability);
  assert.deepEqual(currentEngineCapability, baseCapability,
    "finalize engine capability differs byte-for-byte from local v4 C");
  assert.deepEqual(coordinatorManifest.fullCapability.refreshedSourceState,
    currentEngineCapability.sourceState);
  assert.deepEqual(coordinatorManifest.engine.sourceState,
    currentEngineCapability.sourceState);
  intakeModule.validateSwanSongCaptureIntakeCapabilityReceipt(
    JSON.parse(fs.readFileSync(intakeCapabilityPath, "utf8")),
    { toolkitRoot, nodeExecutable: nodePath, fixtureRoot },
  );
  authModule.validateSwanSongCapturePlanBootstrapCapability({
    baseCapabilityReceiptPath: baseCapabilityPath,
    captureIntakeCapabilityReceiptPath: intakeCapabilityPath,
    bootstrapCapabilityPath: bootstrapPath,
    toolkitRoot,
    nodeExecutable: nodePath,
    captureIntakeFixtureRoot: fixtureRoot,
  });

  assert.equal(coordinatorManifest.publicFixture.projectRoot, projectRoot);
  validateFileBinding(coordinatorManifest.publicFixture.projectManifest,
    "public project manifest", { mode: FILE_MODE });
  const planBinding = { ...coordinatorManifest.publicFixture.plan };
  delete planBinding.totalFrames;
  validateFileBinding(planBinding, "public 30-frame plan", { mode: FILE_MODE });
  assert.equal(coordinatorManifest.publicFixture.plan.totalFrames, 30);
  assert.equal(JSON.parse(fs.readFileSync(planPath, "utf8")).totalFrames, 30);
  validateFileBinding(coordinatorManifest.publicFixture.originalROM,
    "public Original ROM", { mode: FILE_MODE });
  validateFileBinding(coordinatorManifest.publicFixture.patchedROM,
    "public Patched ROM", { mode: FILE_MODE });
  assert.deepEqual(coordinatorManifest.publicFixture.originalROM.artifact,
    coordinatorManifest.publicFixture.patchedROM.artifact);
  assert.equal(coordinatorManifest.publicFixture.sameROMRequired, true);

  const { success: successNonce, blocked: blockedNonce, overBound: overBoundNonce } =
    coordinatorManifest.planned.nonces;
  for (const nonce of [successNonce, blockedNonce, overBoundNonce]) {
    assert.match(nonce, /^[0-9a-f]{64}$/u);
  }
  assert.equal(new Set([successNonce, blockedNonce, overBoundNonce]).size, 3);
  const successGraph = plannedRunGraph({
    root: temporaryRoot, projectRoot, nonceLedger, name: "success",
    nonce: successNonce, status: "complete",
  });
  const blockedGraph = plannedRunGraph({
    root: temporaryRoot, projectRoot, nonceLedger, name: "blocked",
    nonce: blockedNonce, status: "blocked",
  });
  assert.deepEqual(coordinatorManifest.planned.success, successGraph);
  assert.deepEqual(coordinatorManifest.planned.blocked, blockedGraph);
  const overBoundRunDirectory = path.join(projectRoot, "runs", "over-bound");
  const overBoundNonceClaimPath = path.join(nonceLedger, `${overBoundNonce}.json`);
  const overBoundRequestPath = path.join(controlsDirectory, "over-bound.request.json");
  const overBoundPreclaimPath = path.join(controlsDirectory, "over-bound.preclaim.json");
  const overBoundReceiptPath = path.join(controlsDirectory, "over-bound.receipt.json");
  const methodCapabilityPath = path.join(controlsDirectory,
    "capture-plan-method-capability.json");
  assert.deepEqual(coordinatorManifest.planned.overBound, {
    nonce: overBoundNonce,
    nonceClaimPath: overBoundNonceClaimPath,
    runDirectory: overBoundRunDirectory,
    requestPath: overBoundRequestPath,
    preclaimPath: overBoundPreclaimPath,
    receiptPath: overBoundReceiptPath,
  });
  assert.equal(coordinatorManifest.planned.successPhaseReceiptPath,
    successPhaseReceiptPath);
  assert.equal(coordinatorManifest.planned.methodCapabilityPath, methodCapabilityPath);
  assert.equal(coordinatorManifest.planned.finalBundleManifestPath,
    finalBundleManifestPath);
  const successAdditions = [
    plannedEntry(temporaryRoot, coordinatorManifestPath, "file", FILE_MODE),
    ...successGraph.additions,
    plannedEntry(temporaryRoot, successPhaseReceiptPath, "file", FILE_MODE),
  ].sort((left, right) => left.relativePath.localeCompare(right.relativePath));
  const finalizeAdditions = [
    ...blockedGraph.additions,
    plannedEntry(temporaryRoot, overBoundRequestPath, "file", FILE_MODE),
    plannedEntry(temporaryRoot, overBoundPreclaimPath, "file", FILE_MODE),
    plannedEntry(temporaryRoot, overBoundReceiptPath, "file", FILE_MODE),
    plannedEntry(temporaryRoot, methodCapabilityPath, "file", FILE_MODE),
    plannedEntry(temporaryRoot, finalBundleManifestPath, "file", FILE_MODE),
  ].sort((left, right) => left.relativePath.localeCompare(right.relativePath));
  assert.deepEqual(coordinatorManifest.allowedTwoPhaseAdditions.success,
    successAdditions);
  assert.deepEqual(coordinatorManifest.allowedTwoPhaseAdditions.finalize,
    finalizeAdditions);
  assert.equal(coordinatorManifest.allowedTwoPhaseAdditions.extraOutputRuntimeAllowed,
    false);
  assert.equal(coordinatorManifest.allowedTwoPhaseAdditions.crossMethodRuntimeAllowed,
    false);

  assert.deepEqual(successPhaseReceipt.coordinatorManifest,
    fileBinding(coordinatorManifestPath, "coordinator manifest", { mode: FILE_MODE }));
  assert.equal(successPhaseReceipt.phaseOneTreeBeforeReceiptSHA256,
    treeSHA256(successPhaseReceipt.phaseOneTreeBeforeReceipt));
  assert.deepEqual(retainedBeforeReceipt, successPhaseReceipt.phaseOneTreeBeforeReceipt,
    "retained phase-one tree changed before finalize");
  const retainedPhaseOneTree = treeIdentity(temporaryRoot);
  assertExactTreeShape(retainedPhaseOneTree, [
    ...exactTreeShape(coordinatorManifest.preparedTree), ...successAdditions,
  ], "retained phase-one tree/receipt differs from the manifest");
  assertPrivateTree(retainedPhaseOneTree, "retained phase-one bundle");

  const successAuthorization = authModule.validateSwanSongCapturePlanAuthorization({
    baseCapabilityReceiptPath: baseCapabilityPath,
    captureIntakeCapabilityReceiptPath: intakeCapabilityPath,
    bootstrapCapabilityPath: bootstrapPath,
    authorizationPath: successGraph.authorizationPath,
    toolkitRoot,
    nodeExecutable: nodePath,
    runnerLauncherPath,
    captureIntakeFixtureRoot: fixtureRoot,
  });
  const success = {
    path: successGraph.authorizationPath,
    runDirectory: successGraph.runDirectory,
    authorization: successAuthorization,
  };
  const retainedSuccess = methodModule.verifyRetainedSwanSongCapturePlanControl({
    authorizationPath: success.path,
    baseCapabilityReceiptPath: baseCapabilityPath,
    captureIntakeCapabilityReceiptPath: intakeCapabilityPath,
    bootstrapCapabilityPath: bootstrapPath,
    expectedStatus: "complete",
  });
  const successProof = validateClosure({
    authorization: success.authorization,
    expectedStatus: "complete",
    expectedPayloadRoles: PAYLOAD_ROLES,
  });
  assert.deepEqual(successPhaseReceipt.success.retainedControl, retainedSuccess);
  assert.equal(successPhaseReceipt.success.payloadArtifactCount,
    successProof.closure.privateArtifacts.count);
  assert.equal(successPhaseReceipt.success.sameROMNativeZeroDiff, true);
  assert.equal(successPhaseReceipt.success.exactPlanFrames, 30);
  assert.equal(successPhaseReceipt.success.executionCount, 1);
  validateFileBinding(successPhaseReceipt.success.authorization,
    "success authorization", { mode: FILE_MODE });
  validateFileBinding(successPhaseReceipt.success.closure,
    "success closure", { mode: FILE_MODE });
  validateFileBinding(successPhaseReceipt.success.report,
    "success report", { mode: FILE_MODE });
  validateLaneWitness({ authorization: success.authorization, lane: "original",
    toolkitRoot, projectRoot, nodePath });
  validateLaneWitness({ authorization: success.authorization, lane: "patched",
    toolkitRoot, projectRoot, nodePath });

  requireAbsent(finalizeAdditions.map((entry) =>
    path.join(temporaryRoot, ...entry.relativePath.split("/"))),
  "finalize destination");
  requireAbsent([overBoundRunDirectory, overBoundNonceClaimPath],
    "over-bound attempted target");

  function issueAuthorization({ name, nonce, faultInjection = null, selectedPlan = planPath }) {
    const runDirectory = path.join(projectRoot, "runs", name);
    if (fs.existsSync(runDirectory)) fail(`run directory ${name} is not fresh`);
    return authModule.createSwanSongCapturePlanAuthorization({
      baseCapabilityReceiptPath: baseCapabilityPath,
      captureIntakeCapabilityReceiptPath: intakeCapabilityPath,
      bootstrapCapabilityPath: bootstrapPath,
      toolkitRoot,
      nodeExecutable: nodePath,
      runnerLauncherPath,
      captureIntakeFixtureRoot: fixtureRoot,
      nonceLedgerDirectory: nonceLedger,
      nonce,
      runDirectory,
      projectRoot,
      projectManifestPath: path.join(projectRoot, "project.json"),
      planPath: selectedPlan,
      originalROMPath: path.join(projectRoot, "rom", "original.ws"),
      patchedROMPath: path.join(projectRoot, "build", "patched.ws"),
      routeRunnerPath: runnerPath,
      loadedDylibPath: coordinatorManifest.engine.loadedDylib.canonicalPath,
      faultInjection,
    });
  }
  function launchAuthorized(authorization) {
    return run(nodePath, [runnerLauncherPath, "--authorization", authorization.path],
      runnerEnvironment);
  }

  const blocked = issueAuthorization({
    name: "blocked",
    nonce: blockedNonce,
    faultInjection: "after-original-complete",
  });
  const blockedResult = launchAuthorized(blocked);
  requireSuccess(blockedResult, "authorized blocked-prefix control");
  const retainedBlocked = methodModule.verifyRetainedSwanSongCapturePlanControl({
    authorizationPath: blocked.path,
    baseCapabilityReceiptPath: baseCapabilityPath,
    captureIntakeCapabilityReceiptPath: intakeCapabilityPath,
    bootstrapCapabilityPath: bootstrapPath,
    expectedStatus: "blocked",
  });
  const blockedProof = validateClosure({
    authorization: blocked.authorization,
    expectedStatus: "blocked",
    expectedPayloadRoles: PAYLOAD_ROLES.slice(0, 8),
  });
  assert.equal(blockedProof.report.sealedPayloadPrefixLength, 8);
  assert.deepEqual(blockedProof.report.sealedPayloadRoles, PAYLOAD_ROLES.slice(0, 8));
  validateLaneWitness({ authorization: blocked.authorization, lane: "original",
    toolkitRoot, projectRoot, nodePath });

  writePrivateJSON(overBoundRequestPath, {
    schema: methodModule.SWANSONG_CAPTURE_PLAN_OVER_BOUND_REQUEST_SCHEMA,
    authorizationArguments: {
      baseCapabilityReceiptPath: baseCapabilityPath,
      bootstrapCapabilityPath: bootstrapPath,
      captureIntakeCapabilityReceiptPath: intakeCapabilityPath,
      captureIntakeFixtureRoot: fixtureRoot,
      faultInjection: null,
      loadedDylibPath: coordinatorManifest.engine.loadedDylib.canonicalPath,
      nodeExecutable: nodePath,
      nonce: overBoundNonce,
      nonceLedgerDirectory: nonceLedger,
      originalROMPath: path.join(projectRoot, "rom", "original.ws"),
      patchedROMPath: path.join(projectRoot, "build", "patched.ws"),
      planPath: overBoundPlan,
      projectManifestPath: path.join(projectRoot, "project.json"),
      projectRoot,
      routeRunnerPath: runnerPath,
      runnerLauncherPath,
      runDirectory: overBoundRunDirectory,
      toolkitRoot,
    },
    watchedRoots: [
      {
        label: "nonce-ledger",
        canonicalPath: nonceLedger,
        canonicalPathSHA256: pathSHA256(nonceLedger),
      },
      {
        label: "public-project",
        canonicalPath: projectRoot,
        canonicalPathSHA256: pathSHA256(projectRoot),
      },
    ],
  });

  const methodOptions = {
    baseCapabilityReceiptPath: baseCapabilityPath,
    captureIntakeCapabilityReceiptPath: intakeCapabilityPath,
    bootstrapCapabilityPath: bootstrapPath,
    toolkitRoot,
    nodeExecutable: nodePath,
    runnerLauncherPath,
    captureIntakeFixtureRoot: fixtureRoot,
    successAuthorizationPath: success.path,
    blockedAuthorizationPath: blocked.path,
    overBoundRequestPath,
    overBoundPreclaimPath,
    overBoundReceiptPath,
    overBoundHelperPath,
    engineCapabilityOptions,
    outputPath: methodCapabilityPath,
  };
  const methodCapability = methodModule.createSwanSongCapturePlanMethodCapability(
    methodOptions,
  );
  const validatedMethodCapability = methodModule.validateSwanSongCapturePlanMethodCapability({
    ...methodOptions,
    methodCapabilityPath,
  });
  assert.deepEqual(validatedMethodCapability, methodCapability.receipt);
  assert.equal(validatedMethodCapability.publicControlsPassed, true);
  assert.equal(validatedMethodCapability.commercialExecutionAuthorizedByM1Alone, false);
  assert.equal(validatedMethodCapability.commercialAuthorizationImplemented, false);
  assert.equal(validatedMethodCapability.promotionEligibleByM1Alone, false);
  assert.equal(fs.existsSync(overBoundRunDirectory), false);
  assert.equal(fs.existsSync(overBoundNonceClaimPath), false);

  const finalTreeBeforeManifest = treeIdentity(temporaryRoot);
  assertExactTreeShape(finalTreeBeforeManifest, [
    ...exactTreeShape(coordinatorManifest.preparedTree),
    ...successAdditions,
    ...finalizeAdditions.filter((entry) =>
      entry.relativePath !== relativeInside(temporaryRoot, finalBundleManifestPath,
        "final bundle manifest")),
  ], "finalize phase wrote outside its complete planned graph");
  assertTreeRecordsPreserved(finalTreeBeforeManifest, retainedPhaseOneTree,
    "finalize phase changed retained success evidence or prepared inputs");
  assertPrivateTree(finalTreeBeforeManifest, "final tree before manifest");

  const finalBundleManifest = {
    schema: "swan-song-authorized-capture-plan-durable-bundle-v2",
    phases: ["success", "finalize"],
    publicFixtureOnly: true,
    diagnosticOnly: true,
    commercialExecutionAuthorized: false,
    commercialROMIdentityProven: false,
    commercialOwnershipProven: false,
    promotionEligible: false,
    coordinatorManifest: fileBinding(coordinatorManifestPath, "coordinator manifest", {
      mode: FILE_MODE,
    }),
    successPhaseReceipt: fileBinding(successPhaseReceiptPath,
      "success-phase receipt", { mode: FILE_MODE }),
    fullCapability: fileBinding(baseCapabilityPath, "bundle-local full C", {
      mode: FILE_MODE,
    }),
    captureIntakeCapability: fileBinding(intakeCapabilityPath,
      "Capture Intake capability", { mode: FILE_MODE }),
    bootstrapCapability: fileBinding(bootstrapPath, "capture-plan M0", {
      mode: FILE_MODE,
    }),
    success: {
      authorization: fileBinding(success.path, "success authorization", {
        mode: FILE_MODE,
      }),
      closure: fileBinding(path.join(success.runDirectory, "closure.json"),
        "success closure", { mode: FILE_MODE }),
      payloadArtifactCount: successProof.closure.privateArtifacts.count,
      sameROMNativeZeroDiff: true,
      exactPlanFrames: 30,
      executionCount: 1,
    },
    blocked: {
      authorization: fileBinding(blocked.path, "blocked authorization", {
        mode: FILE_MODE,
      }),
      closure: fileBinding(path.join(blocked.runDirectory, "closure.json"),
        "blocked closure", { mode: FILE_MODE }),
      retainedControl: retainedBlocked,
      payloadArtifactCount: blockedProof.closure.privateArtifacts.count,
      executionCount: 1,
    },
    overBound: {
      request: fileBinding(overBoundRequestPath, "over-bound request", {
        mode: FILE_MODE,
      }),
      preclaim: fileBinding(overBoundPreclaimPath, "over-bound preclaim", {
        mode: FILE_MODE,
      }),
      receipt: fileBinding(overBoundReceiptPath, "over-bound receipt", {
        mode: FILE_MODE,
      }),
      noProjectOrNonceWrite: true,
    },
    methodCapability: fileBinding(methodCapabilityPath,
      "capture-plan method capability", { mode: FILE_MODE }),
    excludedRuntimeControls: {
      extraOutputExecuted: false,
      crossMethodExecuted: false,
    },
    finalTreeBeforeManifest,
    finalTreeBeforeManifestSHA256: treeSHA256(finalTreeBeforeManifest),
  };
  writePrivateJSON(finalBundleManifestPath, finalBundleManifest);
  const completedTree = treeIdentity(temporaryRoot);
  assertExactTreeShape(completedTree, [
    ...exactTreeShape(coordinatorManifest.preparedTree),
    ...successAdditions,
    ...finalizeAdditions,
  ], "final durable bundle differs from the pre-authorized two-phase graph");
  assertTreeRecordsPreserved(completedTree, finalTreeBeforeManifest,
    "final manifest creation changed retained bundle evidence");
  assertPrivateTree(completedTree, "completed durable bundle");

  process.stdout.write(`${JSON.stringify({
    schema: "swan-song-authorized-capture-plan-kat-phase-summary-v1",
    status: "finalized",
    publicFixtureOnly: true,
    exactPlanFrames: 30,
    successExecutionCount: 1,
    blockedExecutionCount: 1,
    successPayloadCount: successProof.closure.privateArtifacts.count,
    blockedPayloadCount: blockedProof.closure.privateArtifacts.count,
    overBoundNoWrite: true,
    extraOutputRuntimeExecuted: false,
    crossMethodRuntimeExecuted: false,
    fullCapabilitySHA256: expectedFullC_SHA256,
    methodCapabilitySHA256: identityOnly(methodCapabilityPath).sha256,
    bundleManifestSHA256: identityOnly(finalBundleManifestPath).sha256,
    durableBundle: temporaryRoot,
    commercialExecutionAuthorized: false,
    commercialROMIdentityProven: false,
    commercialOwnershipProven: false,
    promotionEligible: false,
  }, null, 2)}\n`);
}
