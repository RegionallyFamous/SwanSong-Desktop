#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent
FRAMEWORK_FIXTURE = ROOT / "scripts" / "selftest_light_novel_framework.py"
FORGE = ROOT / "scripts" / "forge.py"


def fixture_module():
    spec = importlib.util.spec_from_file_location("story_forge_reference_base", FRAMEWORK_FIXTURE)
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load the schema-v3 reference base")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def scene(
    base: dict,
    scene_id: str,
    chapter_id: str,
    because_of: str,
    *,
    location: str,
    time: str,
    goal: str,
    pressure: str,
    turn: str,
    decision: str,
    consequence: str,
    entering: str,
    exiting: str,
    image: str,
    tone: str,
    chemistry: str,
    question: str,
    setup_ids: list[str] | None = None,
    payoff_ids: list[str] | None = None,
) -> dict:
    value = copy.deepcopy(base)
    value.update(
        {
            "id": scene_id,
            "chapter_id": chapter_id,
            "pov": "protagonist",
            "participants": ["protagonist", "foil"],
            "location": location,
            "time": time,
            "goal": goal,
            "pressure": pressure,
            "turn": turn,
            "decision": decision,
            "consequence": consequence,
            "entering_state": entering,
            "exit_state": exiting,
            "because_of": because_of,
            "setup_ids": setup_ids or [],
            "payoff_ids": payoff_ids or [],
            "sensory_anchor": "Cardamom, wet iron, orange peel, and the station clock's dry tick",
            "specific_image": image,
            "comic_or_tonal_move": tone,
            "chemistry_move": chemistry,
            "reader_question": question,
            "word_target": 285,
        }
    )
    return value


def manifest() -> dict:
    base = fixture_module().story_manifest()
    base["stage"] = "draft"
    base["identity"].update(
        {
            "format": "reference-short-light-novel",
            "target_words": 1_700,
            "one_sentence_promise": "A missed train and an impossible key force a precise tea seller to let grief become shared responsibility.",
        }
    )
    base["rights_release"].update(
        {
            "rights_holder": "SwanSong Story Forge reference project",
            "attribution": "Original reference fiction maintained in the SwanSong Story Forge repository.",
            "restrictions": ["Private reference project; human release review remains pending."],
            "reviewer": "Story Forge project maintainer",
            "release_statement": "The original private reference lane permits local editorial and adaptation demonstrations only.",
        }
    )
    base["development"]["research_questions"] = [
        "How do small railway kiosks divide opening, cash, food-safety, and closing responsibility?"
    ]
    base_scene = base["scenes"][0]
    base["scenes"] = [
        scene(base_scene, "scene-01", "chapter-01", "opening", location="Shuttered platform-four tea kiosk", time="Five minutes before the last train", goal="Mara wants to board with the impossible parcel and investigate alone", pressure="Teo reveals that Lio's brass key opened a locker and the train is leaving", turn="Orange sugar on the key proves the parcel is tied to Lio's private recipe", decision="Mara misses the train and asks Teo to lead her to the locker", consequence="Investigation becomes shared and the dead kiosk clock wakes", entering="Mara treats grief and the key as private property", exiting="Mara sacrifices her planned departure to follow Teo's evidence", image="The last train leaves while an unplugged clock ticks once", tone="Teo's emergency-reliquary defense makes room for the cost of Mara staying", chemistry="Mara accepts Teo as a witness rather than only a borrower", question="How can Lio's handwriting and recipe sugar be fresh?", setup_ids=["key-wear"]),
        scene(base_scene, "scene-02", "chapter-01", "scene-01", location="Locker corridor behind the dead timetable", time="Minutes after the last train", goal="Mara wants a chronological account from the caretaker", pressure="Mr. Vale denies the parcel while knowing impossible station etiquette", turn="The claim ticket reveals a hidden drawer Lio prepared", decision="Mara uses anger as leverage and orders the hatch opened", consequence="Six envelopes and a recipe ledger turn the haunting into a planned test", entering="Mara believes the impossible evidence is a violation", exiting="Mara recognizes that Lio designed the night around her choices", image="Six dated envelopes wait behind a dead timetable", tone="Official ghost etiquette escalates the interrogation without canceling Mara's grief", chemistry="Teo's observational skill earns him room inside Mara's family mystery", question="What choice did Lio expect Mara to give Teo?"),
        scene(base_scene, "scene-03", "chapter-02", "scene-02", location="Dark kiosk under the blue service lamp", time="Near midnight", goal="Mara wants Lio's ledger to specify the correct inheritance", pressure="The final recipe contains a relational test instead of quantities", turn="Teo declines the choice because Mara's exhaustion would make consent hollow", decision="Mara accepts his refusal rather than forcing a ceremonial handoff", consequence="The clock points them toward an instruction to make the wrong tea together", entering="Mara equates offering the ledger with genuinely sharing authority", exiting="Mara understands that timing and consent matter more than the gesture", image="A blank recipe card lies between two unused train tickets", tone="Customer complaints make Lio's posthumous planning affectionate and maddening", chemistry="Teo rejects unearned permission and becomes trustworthy", question="What will the deliberately wrong tea reveal?", setup_ids=["blank-recipe"]),
        scene(base_scene, "scene-04", "chapter-02", "scene-03", location="Kiosk counter opened to the rainy platform", time="Midnight", goal="Mara and Teo try to create the Orange Platform Blend", pressure="Every ingredient choice exposes a habit they use to avoid honest conflict", turn="Teo confesses he refused Lio's earlier offer and concealed it from Mara", decision="Mara asks what the blend needs instead of what Lio would have done", consequence="Teo's absurd pinch of salt works and the timetable reveals platform zero", entering="Mara protects precision as Lio's unchanged standard", exiting="Mara permits Teo's distinct judgment to improve the recipe", image="Rain air enters as salt quiets an overbearing cardamom brew", tone="Terrible tea and complaint paddles escalate until sincerity gets an unbroken landing", chemistry="They replace permission-seeking with candid disagreement", question="Who is waiting on a platform that does not exist?", payoff_ids=["blank-recipe"]),
        scene(base_scene, "scene-05", "chapter-03", "scene-04", location="Hidden platform zero beneath painted stars", time="The hour before dawn", goal="Mara serves the new blend and discovers Lio's final intent", pressure="Lio's empty red coat offers a message without the farewell Mara wants", turn="The message asks Mara to teach someone who will change the kiosk", decision="Mara offers Teo a bounded trial and asks him to choose its terms", consequence="Teo accepts responsibility without claiming ownership; the key gains a new label", entering="Mara believes continuity means keeping Lio's work unchanged", exiting="Mara chooses continuity through teaching, wear, and improvement", image="Steam passes through an empty red coat and clears the painted stars", tone="The metaphysical platform stays practical through cups, promises, and governance jokes", chemistry="Mara and Teo negotiate reciprocal responsibility", question="Can the ordinary morning carry this changed agreement?", payoff_ids=["key-wear"]),
        scene(base_scene, "scene-06", "chapter-03", "scene-05", location="Reopened platform-four tea kiosk", time="First commuter train at dawn", goal="Mara and Teo make the trial handoff visible in ordinary work", pressure="Mara must allow the key and recipe to show someone else's choices", turn="A fresh scratch reads as survival rather than damage", decision="Mara gives Teo the dawn shift and lets him open tomorrow's parcel", consequence="The kiosk becomes shared while a new mystery arrives", entering="The agreement exists only in the hidden station", exiting="Their new authority and holiday plan are public, practical, and forward-looking", image="The scratched key catches orange dawn beside an uphill chalk label", tone="Mr. Vale files a grievance against metaphysics before tenderness settles", chemistry="Teo looks for consent; Mara gives it without reclaiming control", question="Who sent the parcel dated tomorrow?"),
    ]
    base["chapters"] = [
        {"id": "chapter-01", "title": "The Key in the Cup", "dramatic_job": "Make Mara sacrifice control long enough to accept shared evidence", "entering_state": "Mara is leaving and Teo is only a borrower", "exit_change": "Mara enters Lio's planned test with Teo beside her", "opening_hook": "A forbidden key arrives in Lio's teacup", "closing_pull": "An envelope predicts the choice Mara has not made", "scene_ids": ["scene-01", "scene-02"]},
        {"id": "chapter-02", "title": "Six Ways to Inherit a Kiosk", "dramatic_job": "Turn a symbolic handoff into earned reciprocal trust", "entering_state": "Mara wants the ledger to decide for her", "exit_change": "Mara asks Teo's judgment to change the recipe", "opening_hook": "Five envelopes complain and the sixth refuses instructions", "closing_pull": "The new tea reveals a platform absent from every map", "scene_ids": ["scene-03", "scene-04"]},
        {"id": "chapter-03", "title": "The Dawn Shift", "dramatic_job": "Make shared responsibility survive the return to ordinary work", "entering_state": "Mara still equates love with preservation", "exit_change": "Mara values wear, teaching, and another person's choices", "opening_hook": "A wall opens onto six delayed passengers", "closing_pull": "Tomorrow's parcel begins a mystery under shared authority", "scene_ids": ["scene-05", "scene-06"]},
    ]
    base["setups"] = [
        {"id": "key-wear", "introduced_in": "scene-01", "payoff_in": "scene-05", "surface_detail": "The brass key carries recipe sugar but Mara protects it from wear", "changed_meaning": "A new scratch proves that Lio's tool survives by entering another responsible hand"},
        {"id": "blank-recipe", "introduced_in": "scene-03", "payoff_in": "scene-04", "surface_detail": "The Orange Platform Blend card names a test but gives no quantities", "changed_meaning": "The missing measurements force Mara and Teo to create a recipe through candid disagreement"},
    ]
    base["motifs"] = [
        {"id": "clock-tick", "element": "The unplugged kiosk clock", "appearances": [
            {"scene_id": "scene-01", "evolution": "One impossible tick marks Mara choosing the investigation"},
            {"scene_id": "scene-03", "evolution": "The minute hand points toward a collaborative instruction"},
            {"scene_id": "scene-06", "evolution": "Normal ticking marks grief becoming daily shared time"},
        ]}
    ]
    base["relationships"][0].update(
        {
            "surface_dynamic": "Exacting kiosk keeper and improvising assistant",
            "buried_need": "Mara needs Teo to accept responsibility without asking her to erase Lio",
            "pressure_point": "Mara mistakes control for care while Teo disguises fear as humor",
            "visible_change": "They negotiate a trial dawn shift and a shared holiday",
            "status_game": "Mara holds formal authority; Teo gains influence by declining hollow permission",
            "friction": "Measurement and precedent versus experiment and candid correction",
            "shared_joke": "Station bureaucracy becomes a safe way to name emotional rules",
            "secret_tenderness": "Teo watches the cost of Mara's choices and refuses to exploit exhaustion",
            "conversation_game": "Mara demands chronology; Teo answers with jokes until a direct answer matters",
            "status_flips": [
                {"scene_id": "scene-03", "change": "Teo gains trust by refusing an unearned choice"},
                {"scene_id": "scene-05", "change": "Mara asks Teo to define the terms of his responsibility"},
            ],
        }
    )
    base["delight"] = {
        "signature_moments": [
            {"id": "delight-01", "chapter_id": "chapter-01", "scene_id": "scene-02", "type": "Humor turning into evidence", "setup": "Teo improvises ghost etiquette", "delivery": "The skeptical caretaker corrects his bow", "reader_effect": "A laugh makes the caretaker's knowledge suspicious", "only_here_reason": "Railway rank and tea hospitality share one absurd bureaucracy"},
            {"id": "delight-02", "chapter_id": "chapter-02", "scene_id": "scene-04", "type": "Competence through surprise", "setup": "Mara's precise attempts make terrible tea", "delivery": "Teo's pinch of salt makes orange and cardamom cohere", "reader_effect": "The practical solution proves his judgment deserves weight", "only_here_reason": "Recipe correction becomes a negotiated inheritance"},
            {"id": "delight-03", "chapter_id": "chapter-03", "scene_id": "scene-05", "type": "Tender catharsis", "setup": "Mara protects Lio through untouched objects", "delivery": "Lio's coat collapses and the key is relabeled for shared wear", "reader_effect": "Absence becomes room for new responsibility", "only_here_reason": "A haunted platform resolves through the ethics of a working tool"},
        ],
        "rhythm": [
            {"scene_id": "scene-01", "tension": 3, "warmth": 1, "humor": 2, "wonder": 2, "dominant_beat": "Impossible arrival", "reader_effect": "Curiosity with a visible emotional cost", "entry_hook": "A forbidden key rests in Lio's cup", "exit_pull": "The dead clock answers the missed train"},
            {"scene_id": "scene-02", "tension": 4, "warmth": 2, "humor": 4, "wonder": 3, "dominant_beat": "Comic interrogation", "reader_effect": "Laughter sharpens rather than dissolves suspicion", "entry_hook": "Tomorrow's claim ticket points beneath the timetable", "exit_pull": "An envelope predicts Mara's unmade choice"},
            {"scene_id": "scene-03", "tension": 3, "warmth": 3, "humor": 2, "wonder": 3, "dominant_beat": "Refused permission", "reader_effect": "Respect grows through an unexpected no", "entry_hook": "The complaints turn inheritance into daily work", "exit_pull": "A note orders them to make the wrong tea"},
            {"scene_id": "scene-04", "tension": 4, "warmth": 4, "humor": 4, "wonder": 2, "dominant_beat": "Candid recipe fight", "reader_effect": "Competence and confession earn a new collaboration", "entry_hook": "The first pot can remove architectural stains", "exit_pull": "A nonexistent platform appears"},
            {"scene_id": "scene-05", "tension": 3, "warmth": 5, "humor": 2, "wonder": 5, "dominant_beat": "Earned handoff", "reader_effect": "Grief opens into negotiated hope", "entry_hook": "Six delayed passengers wait beneath painted stars", "exit_pull": "The hidden agreement must survive morning"},
            {"scene_id": "scene-06", "tension": 1, "warmth": 5, "humor": 3, "wonder": 3, "dominant_beat": "Ordinary proof", "reader_effect": "Relief with appetite for the next mystery", "entry_hook": "The new shift begins under an uphill chalk label", "exit_pull": "A parcel dated tomorrow enters shared hands"},
        ],
    }
    base["continuity_ledger"] = {
        "initial_states": [{"id": "mara-teo-trust", "type": "relationship", "state": "Mara treats Teo as a borrower without authority"}],
        "events": [
            {"id": "trust-refusal", "scene_id": "scene-03", "entity_id": "mara-teo-trust", "before": "Mara treats Teo as a borrower without authority", "after": "Mara trusts Teo to refuse hollow permission", "evidence": "Teo returns the ledger rather than exploiting Mara's exhaustion"},
            {"id": "trust-handoff", "scene_id": "scene-05", "entity_id": "mara-teo-trust", "before": "Mara trusts Teo to refuse hollow permission", "after": "Mara trusts Teo with a negotiated dawn shift", "evidence": "Mara offers the key and asks Teo to choose the terms"},
        ],
        "final_states": [{"entity_id": "mara-teo-trust", "state": "Mara trusts Teo with a negotiated dawn shift"}],
    }
    base["soundtrack_bible"]["release_mode"] = "both"
    base["soundtrack_bible"]["cues"][0]["scene_ids"] = ["scene-01", "scene-05", "scene-06"]
    visual = base["illustration_bible"]
    visual["visual_contract"].update({"style": "Cozy storybook realism with expressive hands, compact railway architecture, and clean readable silhouettes", "palette": "Cardamom brown, timetable blue, rain copper, orange dawn, and restrained supernatural violet", "lighting": "Practical kiosk lamps shift from interrogation blue to open-window rain and warm dawn", "character_consistency": "Mara remains angular and buttoned; Teo remains loose, uphill, and visibly careful around her boundaries"})
    visual["character_designs"][0].update({"silhouette": "Compact angular coat and squared shoulders", "face_hair": "Dark blunt bob, precise brows, tired attentive eyes", "wardrobe": "Buttoned charcoal kiosk coat with orange thread repair", "acting_range": "Control in small hand motions; laughter changes her entire posture"})
    visual["character_designs"][1].update({"silhouette": "Tall loose raincoat and slightly forward hopeful posture", "face_hair": "Soft curls, open brows, quick side glances", "wardrobe": "Oversized blue raincoat over rolled kiosk sleeves", "acting_range": "Jokes in broad gestures; sincerity becomes still and direct"})
    visual["locations"] = [{"id": "location-01", "name": "Platform-four tea kiosk and hidden platform zero", "anchors": ["Unplugged clock", "dead timetable", "painted stars", "blue service lamp"], "mood_range": "Shuttered grief, comic interrogation, uncanny hospitality, and public dawn"}]
    visual["recurring_props"] = [{"id": "prop-01", "name": "Lio's brass key", "continuity_rule": "Begin sugar-dusted and protected; end newly scratched, relabeled, and held by Teo"}]
    visual["moments"][0].update({"scene_id": "scene-01", "narrative_purpose": "Promise grief, comedy, railway mystery, and shared action in one image", "emotional_beat": "Mara chooses the impossible key over the departing train", "composition": "Mara foreground with cup and key; Teo rain-soaked midground; amber train receding behind the shuttered kiosk", "must_show": ["Brass key in Lio's teacup", "Mara's guarded decision", "Departing last train"], "must_avoid": ["Generic standing portrait", "Readable generated lettering", "A literal visible ghost"]})
    visual["moments"][1].update({"scene_id": "scene-05", "narrative_purpose": "Show the emotional handoff rather than merely illustrate the supernatural platform", "emotional_beat": "Mara offers responsibility while Lio's empty coat collapses", "composition": "Key crossing between Mara and Teo at center; empty red coat and painted stars behind; cups forming a quiet arc", "must_show": ["Mara and Teo's hands around the scratched key", "Empty red coat", "Painted-star platform"], "must_avoid": ["Lio shown as a person", "Broad melodramatic crying", "Repeated cover composition"]})
    base["quality"].update({"minimum_scenes": 6, "minimum_scene_words": 250, "maximum_scene_words": 800, "minimum_setups": 2, "minimum_motifs": 1, "minimum_draft_completion_ratio": 1.0})
    return base


def run(*args: str) -> None:
    result = subprocess.run([sys.executable, str(FORGE), *args], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    print(result.stdout, end="")
    if result.returncode:
        raise RuntimeError(f"Reference command failed: {' '.join(args)}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the honest Story Forge reference novel and workbench.")
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    destination = args.destination.expanduser().resolve()
    if destination.exists():
        raise SystemExit(f"Refusing to overwrite existing reference project: {destination}")
    destination.mkdir(parents=True)
    shutil.copytree(SOURCE / "manuscript", destination / "manuscript")
    manifest_path = destination / "novel.json"
    manifest_path.write_text(json.dumps(manifest(), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    for command in (
        ("story-room", str(manifest_path)),
        ("story-map", str(manifest_path)),
        ("scene-context", str(manifest_path), "--scene", "scene-04"),
        ("research-init", str(manifest_path)),
        ("research-report", str(manifest_path)),
        ("genre-report", str(manifest_path)),
        ("art-room", str(manifest_path)),
        ("music-init", str(manifest_path)),
        ("music-render", str(manifest_path)),
        ("adapt", str(manifest_path)),
        ("check", str(manifest_path), "--stage", "draft"),
    ):
        run(*command)
    print(f"Reference project: {destination}")
    print("Honest blockers: unprimed readers, ImageGen production art/set review, revision evidence, and human release approval.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
