#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROJECT_ROOT = Path(__file__).resolve().parent
GAME_SPEC = ROOT / "games" / "mobile-suit-gundam-summary" / "assets" / "sources" / "game_spec.json"
FIXTURE = ROOT / "scripts" / "selftest_light_novel_framework.py"


def fixture_module():
    spec = importlib.util.spec_from_file_location("story_forge_manifest_base", FIXTURE)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load manifest base: {FIXTURE}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def words(text: str) -> int:
    return len(re.findall(r"[A-Za-z0-9][A-Za-z0-9'’-]*", text))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def authored_text(node: dict) -> str:
    return str(node.get("text") or "").replace("{pause}", " ").strip()


def scene_card(base: dict, *, scene_id: str, because_of: str, node_ids: list[str], nodes: dict[str, dict],
               location: str, time: str, goal: str, pressure: str, turn: str, decision: str,
               consequence: str, entering: str, exiting: str, image: str, tone: str,
               chemistry: str, question: str, setup_ids: list[str] | None = None,
               payoff_ids: list[str] | None = None, question_status: str | None = None) -> dict:
    value = copy.deepcopy(base)
    scene_text = " ".join(authored_text(nodes[node_id]) for node_id in node_ids)
    value.update(
        {
            "id": scene_id,
            "chapter_id": "chapter-01",
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
            "sensory_anchor": "A closing clock ticks over tiny servos, glass reflections, and a cart of blank footnotes.",
            "specific_image": image,
            "comic_or_tonal_move": tone,
            "chemistry_move": chemistry,
            "reader_question": question,
            "word_target": words(scene_text),
            "adaptation_node_ids": node_ids,
        }
    )
    if question_status:
        value["reader_question_status"] = question_status
    return value


def build_manifest(spec: dict) -> tuple[dict, list[tuple[dict, list[str]]]]:
    base = fixture_module().story_manifest()
    nodes = {str(node["id"]): node for node in spec["nodes"]}
    groups = [
        {
            "scene_id": "scene-01",
            "because_of": "opening",
            "node_ids": ["tour_01", "tour_02", "tour_03", "tour_04", "tour_05", "tour_ticket_01"],
            "location": "Universal Century History Museum atrium and opening-war gallery",
            "time": "Twenty minutes before closing",
            "goal": "RX and Zaku must establish a fair causal tour and explain why Amuro enters Gundam",
            "pressure": "A whole year of war must fit before the museum closes without reducing mass death to faction trivia",
            "turn": "The first Gundam victory is reframed as the beginning of a refugee story",
            "decision": "The docents dim the victory lamp and keep the ruined colony visible",
            "consequence": "White Base, not the machine alone, becomes the tour's narrative spine",
            "entering": "The museum labels invite a simple hero-versus-villain reading",
            "exiting": "The docents commit to witness, causality, and civilian consequence",
            "image": "A brilliant Gundam display is dimmed until the ruined Side 7 lights remain visible",
            "tone": "The impossible twenty-minute deadline creates jokes while the docents refuse to joke about victims",
            "chemistry": "RX supplies momentum; Zaku interrupts whenever spectacle hides cost",
            "question": "Can a ship of unprepared survivors keep moving under Char's pursuit?",
            "setup_ids": ["closing-clock", "tour-ticket", "witness-badges", "names-on-glass"],
        },
        {
            "scene_id": "scene-02",
            "because_of": "scene-01",
            "node_ids": ["tour_06", "tour_07", "tour_07b", "tour_08", "tour_09", "whitebase_01", "whitebase_02", "ral_diorama_01"],
            "location": "White Base route gallery",
            "time": "Side 7 escape through Garma's funeral",
            "goal": "Explain how refugees become a crew and how Char turns friendship into revenge",
            "pressure": "Federation protocol, exhaustion, reentry, and Zeon pursuit all narrow White Base's choices",
            "turn": "Char feeds Garma false guidance and Gihren turns the resulting death into propaganda",
            "decision": "The tour follows White Base closely enough to show authority as frightened improvisation",
            "consequence": "Ramba Ral inherits both a military hunt and a chain of private grief",
            "entering": "White Base is an accidental transport full of civilians and prototypes",
            "exiting": "The crew is becoming a family while Char's revenge begins reshaping Zeon command",
            "image": "A route display marks atmospheric reentry as an unfortunate detour lasting most of a campaign",
            "tone": "Museum paperwork and overconfident route labels carry the humor",
            "chemistry": "The docents disagree about lens, then state that history will not change with viewpoint",
            "question": "Will Amuro learn that technical talent cannot substitute for maturity?",
            "setup_ids": ["zabi-board"],
        },
        {
            "scene_id": "scene-03",
            "because_of": "scene-02",
            "node_ids": ["earth_01", "earth_02", "earth_03", "earth_04", "odessa_memorial_01"],
            "location": "Earth campaign and Odessa map gallery",
            "time": "Ramba Ral pursuit through Operation Odessa",
            "goal": "Show Amuro's growth without pretending that victory protects the people around him",
            "pressure": "Family estrangement, desertion, Ral's experience, command strain, and Zeon's nuclear threat converge",
            "turn": "Ryu and Matilda die while White Base becomes strategically indispensable",
            "decision": "Amuro returns to the crew and stops M'Quve's nuclear strike",
            "consequence": "The Federation breaks Zeon's Earth foothold, but victory is experienced as names on glass",
            "entering": "Amuro believes one gifted pilot can solve the mine and his own exhaustion",
            "exiting": "He understands that courage, command, and victory still accumulate human cost",
            "image": "The memorial light remains dark for one full breath before the Odessa map resumes",
            "tone": "The desert refusing to fit Amuro's solo plan on one museum card punctures his certainty",
            "chemistry": "Zaku protects the memorial pause; RX restores the causal military line afterward",
            "question": "What kind of home can White Base become when its members can still choose to leave?",
            "setup_ids": ["chosen-home"],
            "payoff_ids": ["names-on-glass"],
        },
        {
            "scene_id": "scene-04",
            "because_of": "scene-03",
            "node_ids": ["earth_05", "earth_05b", "guide_white_base_01", "earth_06", "earth_07", "earth_07b", "side6_archive_01"],
            "location": "Belfast, Jaburo, and Side 6 galleries",
            "time": "Kai's desertion through the Side 6 battles",
            "goal": "Connect Kai's return, Jaburo's institutional absorption, and Amuro's accelerating ability",
            "pressure": "Miharu's poverty, Char's return, Federation utility, Tem Ray's damage, and neutral-space attacks deny easy safety",
            "turn": "Kai freely returns while the Federation converts White Base into a decoy",
            "decision": "The docents replace a spy token with an empty chair and two lunch tins",
            "consequence": "White Base becomes a chosen home even as its people are made more useful to the war",
            "entering": "Detachment and arrival at Jaburo still look like possible exits",
            "exiting": "Choice creates belonging; formal safety creates new military exposure",
            "image": "An empty chair and two lunch tins replace a red token on the spy exhibit",
            "tone": "A museum counter flashes SKILL and DANGER at the same time",
            "chemistry": "RX emphasizes chosen return; Zaku tracks the institutions monetizing that loyalty",
            "question": "Will Newtype perception become connection or merely faster targeting?",
            "setup_ids": ["newtype-weaponization"],
            "payoff_ids": ["chosen-home"],
        },
        {
            "scene_id": "scene-05",
            "because_of": "scene-04",
            "node_ids": ["space_01", "solomon_memorial_01", "guide_zabi_01", "people_01", "people_02", "people_03", "people_03b"],
            "location": "Side 6, Solomon, Texas, and Newtype galleries",
            "time": "Amuro's meeting with Lalah through Lalah's death",
            "goal": "Explain the Newtype possibility through people before institutions claim it as a weapon",
            "pressure": "Solomon, Sleggar's sacrifice, Char's Deikun identity, and organized Newtype warfare close every peaceful opening",
            "turn": "Amuro and Lalah understand one another across enemy lines, then Lalah dies protecting Char",
            "decision": "Char and Amuro convert shared grief into renewed rivalry",
            "consequence": "The story approaches its final battle with connection recognized but militarily unusable",
            "entering": "Amuro's growing awareness could still widen empathy",
            "exiting": "The war has turned that awareness into targeting and blame",
            "image": "Two gallery-light circles almost overlap, then pull apart after Lalah's death",
            "tone": "A victory lamp notices Sleggar's empty station and dims itself",
            "chemistry": "The docents stop competing over the best lens and let the failed connection occupy the room",
            "question": "Can any command structure end the war before it consumes itself?",
            "setup_ids": ["newtype-connection"],
            "payoff_ids": ["names-on-glass", "newtype-weaponization"],
        },
        {
            "scene_id": "scene-06",
            "because_of": "scene-05",
            "node_ids": ["people_04", "people_05", "people_06", "people_07", "people_coda"],
            "location": "Solar Ray, A Baoa Qu, and sunrise exit gallery",
            "time": "Degwin's peace attempt through the armistice",
            "goal": "Complete the Zabi collapse, final duel, White Base escape, and thematic return home",
            "pressure": "Solar Ray destroys peace and fleets; the Zabis assassinate one another; Gundam, Zeong, and White Base are lost",
            "turn": "Amuro guides the crew out and their voices guide him back",
            "decision": "The docents replace HERO and VILLAIN with WITNESS and wait for everyone to leave together",
            "consequence": "The machines end, the war soon ends, and the relationships survive",
            "entering": "Power appears concentrated in superweapons, fortresses, and command families",
            "exiting": "The decisive system is people recognizing and guiding one another across wreckage",
            "image": "The broken exit arrow becomes a warm path while the tour ticket receives its HOME punch",
            "tone": "The clock reaches zero and politely refuses to close before the group is together",
            "chemistry": "RX and Zaku remove opposing badges and share one witness hook",
            "question": "What should the next museum tour notice that faction colors hide?",
            "question_status": "intentional-open",
            "payoff_ids": ["closing-clock", "tour-ticket", "witness-badges", "zabi-board", "newtype-connection", "names-on-glass"],
        },
    ]
    scene_base = base["scenes"][0]
    scenes = [scene_card(scene_base, nodes=nodes, **group) for group in groups]

    base["stage"] = "draft"
    base["framework"]["workbench_evidence"] = []
    base["workbench"]["lead_writer"] = "human"
    base["workbench"]["merge_policy"] = "proposal-only"
    base["workbench"]["image_policy"] = "imagegen-only"
    base["workbench"]["adaptation"] = {"target": "wonderswan-color", "status": "playable-candidate"}
    base["rights_release"] = {
        "mode": "fan-work",
        "release_scope": "private",
        "rights_holder": "Mobile Suit Gundam rights remain with their respective owners",
        "source_franchises": ["Mobile Suit Gundam (1979 television series)"],
        "attribution": "Unofficial noncommercial fan work; new commentary, ImageGen fan art, and original sound effects by the Story Forge project.",
        "restrictions": ["Private study/play only", "No commercial release", "Public distribution requires a separate rights decision"],
        "commercial_clearance": "not-applicable",
        "reviewer": "Human project maintainer review pending",
        "release_statement": "The private fan-work lane permits local research, writing, build, and testing without claiming public distribution rights.",
    }
    base["identity"] = {
        "slug": "mobile-suit-gundam-summary",
        "title": "Mobile Suit Gundam: The One Year Tour",
        "format": "branching-visual-novel-source-manuscript",
        "audience": "Gundam newcomers and returning fans who want a fast, causal, full-spoiler tour",
        "genres": ["science fiction", "historical museum comedy", "war drama"],
        "point_of_view": "First-person museum-docent frame alternating between Docent RX and Docent Zaku",
        "tense": "Present-tense museum frame with past-tense historical summary",
        "target_words": sum(scene["word_target"] for scene in scenes),
        "one_sentence_promise": "Two tiny mobile-suit docents race closing time to trace one year of war through causes, consequences, grief, and one path home.",
    }
    base["development"] = {
        "premise_candidates": [
            {"id": "candidate-01", "hook": "A tiny museum's last tour must cross the One Year War before closing", "relationship_engine": "RX supplies momentum while Zaku protects context and consequence", "story_engine": "Every exhibit answers what changed and why the next crisis followed", "ending_pressure": "The clock reaches zero during A Baoa Qu", "derivative_risk": "Low framing risk; canon facts require strict sourcing"},
            {"id": "candidate-02", "hook": "White Base files an after-action report from the future", "relationship_engine": "Conflicting witnesses correct one another", "story_engine": "Report exhibits unlock chronologically", "ending_pressure": "The report must decide what counts as victory", "derivative_risk": "Too close to character impersonation and transcript voice"},
            {"id": "candidate-03", "hook": "A model-kit assembly manual keeps revealing the war around each part", "relationship_engine": "Builder and manual argue over spectacle versus cost", "story_engine": "Each component opens a campaign leg", "ending_pressure": "The completed Gundam must be abandoned", "derivative_risk": "Product framing could overwhelm people"},
            {"id": "candidate-04", "hook": "A colony classroom compresses the One Year War into one period", "relationship_engine": "Teacher and student test heroic assumptions", "story_engine": "Questions force causal detours", "ending_pressure": "The bell rings at A Baoa Qu", "derivative_risk": "Human framing cast would demand separate art and arc"},
            {"id": "candidate-05", "hook": "Two map tokens discover they represent factions rather than people", "relationship_engine": "Opposing tokens become cooperative witnesses", "story_engine": "Campaign arrows expose missing human stories", "ending_pressure": "The board destroys its own command pieces", "derivative_risk": "Abstraction risks emotional distance"},
        ],
        "selected_premise_id": "candidate-01",
        "selection_reason": "The museum supports SD robot comedy, explicit source labels, causal exhibits, visual callbacks, and interpretive choices without impersonating series characters.",
        "research_questions": [
            "Which facts belong only to the original television continuity?",
            "What must remain distinct between Solar System and Solar Ray?",
            "Which episode events can merge without breaking the causal chain?",
            "How can choices alter emphasis without altering canon?",
        ],
    }
    base["creative_contract"].update(
        {
            "hook": "Two SD mobile-suit docents have twenty minutes to cross the One Year War before their museum closes.",
            "emotional_question": "Can a war story leave its machines behind and still show why people find one another?",
            "thematic_argument": "Systems turn perception into weapons, but recognition between people creates the route home.",
            "comic_or_dramatic_engine": "Closing-time museum bureaucracy keeps colliding with a history too large and painful for its labels.",
            "ending_aftertaste": "Warm exit light, a HOME punch in the tour ticket, and two discarded faction badges.",
            "signature_question": "How did two tiny enemy-shaped docents make a year of war feel like one human chain?",
            "originality_boundaries": ["No transcript dialogue", "No recreation of series shots", "No borrowed score or lyrics", "No pilot impersonation by the docents"],
            "non_goals": ["Compilation-film continuity", "The Origin backstory", "Later Universal Century retcons", "A battle-by-battle mechanical catalog"],
        }
    )
    base["genre_profile"].update(
        {
            "module": "science-fiction",
            "primary_pleasure": "Seeing a vast war become one understandable causal chain without losing its human cost",
            "secondary_pleasures": ["Tiny-robot museum comedy", "Strategic clarity", "Emotional callbacks", "Newtype tragedy"],
            "reader_expectations": ["The technology changes ordinary survival", "Political systems create second-order consequences", "The ending makes the speculative question personal"],
            "freshness_move": "A last museum tour lets living machines critique the heroic labels placed on machines.",
            "forbidden_shortcuts": ["No continuity soup", "No fight list", "No unexplained name avalanche", "No jokes aimed at casualties"],
            "module_checks": [
                {"id": "speculative-constraint", "expectation": "Mobile suits change the balance and daily survival", "planned_delivery": "Side 7 turns a weapons test into a refugee ship crewed by civilians", "payoff_scene": "scene-01"},
                {"id": "systemic-consequence", "expectation": "Institutions turn people and perception into military utility", "planned_delivery": "Jaburo converts White Base into a decoy and Newtype connection into targeting", "payoff_scene": "scene-05"},
                {"id": "emotional-payoff", "expectation": "The speculative question resolves through a personal choice", "planned_delivery": "Amuro abandons Gundam and returns to the crew that guides him", "payoff_scene": "scene-06"},
            ],
        }
    )
    base["series"].update(
        {
            "mode": "standalone",
            "series_id": "series-summary-visual-novels",
            "volume_number": 1,
            "series_promise": "Each standalone cartridge explains one declared series continuity through causal exhibits and canon-safe lenses.",
            "volume_promise": "This volume resolves the original Mobile Suit Gundam television chronology through Escape.",
            "character_arc_position": "The docents move from opposing faction badges to a shared WITNESS badge.",
            "continuity_in": [],
            "continuity_out": [],
            "canon": [{"id": "original-tv-only", "statement": "Only the original 1979 television continuity is authoritative for this volume"}],
            "protected_mysteries": [],
            "future_hooks": ["A later cartridge may apply the same method to a separately declared Gundam continuity"],
        }
    )
    base["cast"] = [
        {
            "id": "protagonist", "name": "Docent RX", "role": "lead museum docent", "external_want": "Complete the whole tour before closing", "internal_need": "Stop treating a brilliant machine as the sufficient explanation", "false_belief": "Momentum and clean labels can carry the history", "vulnerability": "RX resembles the icon most likely to swallow the people around it", "contradiction": "Cheerful about procedure and severe about heroic simplification", "behavioral_tell": "Punches the tour ticket whenever a causal link lands", "voice": {"sentence_shape": "Clear causal statements followed by one dry museum observation", "diction": "precise, welcoming, concrete", "avoids": "triumphalism and pilot impersonation", "metaphor_source": "labels, lamps, exits, and maintenance", "sample_required": True},
        },
        {
            "id": "foil", "name": "Docent Zaku", "role": "counterpoint museum docent", "external_want": "Keep every omitted footnote honest", "internal_need": "Accept that context can be concise without becoming propaganda", "false_belief": "Enough footnotes can prevent every harmful simplification", "vulnerability": "Zaku resembles the mass-produced enemy symbol used to erase ordinary soldiers", "contradiction": "Pedantic about sources and quick with self-directed faction jokes", "behavioral_tell": "Rolls an overloaded cart into frame before correcting a label", "voice": {"sentence_shape": "Context first, consequence second, compact joke last", "diction": "wry, archival, humane", "avoids": "mocking casualties or excusing command", "metaphor_source": "maps, filing systems, tokens, and exhibit glass", "sample_required": True},
        },
    ]
    base["relationships"] = [
        {
            "id": "docent-partnership", "characters": ["protagonist", "foil"], "surface_dynamic": "Opposing mobile-suit silhouettes sharing one museum shift", "buried_need": "Each needs the other's lens to avoid spectacle or footnote paralysis", "pressure_point": "The closing clock rewards speed while the history demands care", "visible_change": "They remove HERO and VILLAIN and share WITNESS", "status_game": "RX controls tour momentum; Zaku can stop the lamp or correct the label", "friction": "Narrative clarity versus contextual completeness", "shared_joke": "The museum's labels and bureaucracy are less prepared than either docent", "secret_tenderness": "Each protects the human cost the other's silhouette could obscure", "conversation_game": "One states the clean version; the other reveals the cost or causal exception", "status_flips": [{"scene_id": "scene-01", "change": "Zaku dims the victory lamp and sets the ethical tour rule"}, {"scene_id": "scene-06", "change": "RX and Zaku surrender opposing badges together"}],
        }
    ]
    base["scenes"] = scenes
    base["chapters"] = [
        {"id": "chapter-01", "title": "Last Tour Before Closing", "dramatic_job": "Turn a year of war into one causal and emotionally honest museum tour", "entering_state": "Faction labels and machine spectacle dominate the exhibits", "exit_change": "The docents and player leave with a relationship-centered causal map", "opening_hook": "The last tour begins with twenty minutes on the clock", "closing_pull": "The HOME punch asks what the next tour should notice", "scene_ids": [scene["id"] for scene in scenes]}
    ]
    base["setups"] = [
        {"id": "closing-clock", "introduced_in": "scene-01", "payoff_in": "scene-06", "payoff_scene": "scene-06", "surface_detail": "The museum will close in twenty minutes", "changed_meaning": "The clock waits at zero until everyone leaves together"},
        {"id": "tour-ticket", "introduced_in": "scene-01", "payoff_in": "scene-06", "payoff_scene": "scene-06", "surface_detail": "A blank ticket receives one punch per causal stop", "changed_meaning": "The final punch is HOME rather than a faction or weapon"},
        {"id": "witness-badges", "introduced_in": "scene-01", "payoff_in": "scene-06", "payoff_scene": "scene-06", "surface_detail": "RX and Zaku visually invite HERO and VILLAIN labels", "changed_meaning": "Both labels are replaced by a shared WITNESS badge"},
        {"id": "zabi-board", "introduced_in": "scene-02", "payoff_in": "scene-06", "payoff_scene": "scene-06", "surface_detail": "Red string connects the Zabi command family", "changed_meaning": "The family weaponizes itself until the board pulls apart"},
        {"id": "chosen-home", "introduced_in": "scene-03", "payoff_in": "scene-04", "payoff_scene": "scene-04", "surface_detail": "Amuro, Kai, and the civilians can still leave a crew formed by emergency", "changed_meaning": "Kai's voluntary return makes White Base a home rather than only an assignment"},
        {"id": "newtype-weaponization", "introduced_in": "scene-04", "payoff_in": "scene-05", "payoff_scene": "scene-05", "surface_detail": "Amuro's ability grows faster than command can understand", "changed_meaning": "Both sides answer wider perception by building organized Newtype warfare"},
        {"id": "newtype-connection", "introduced_in": "scene-05", "payoff_in": "scene-06", "payoff_scene": "scene-06", "surface_detail": "Two light circles almost overlap for Amuro and Lalah", "changed_meaning": "Mutual guidance at Escape realizes connection outside targeting"},
        {"id": "names-on-glass", "introduced_in": "scene-01", "payoff_in": "scene-06", "payoff_scene": "scene-06", "surface_detail": "Museum labels initially privilege victories and machines", "changed_meaning": "The final witness label preserves the people hidden beneath campaign outcomes"},
    ]
    base["motifs"] = [
        {"id": "exit-path", "element": "Broken museum arrow and luminous exit path", "appearances": [{"scene_id": "scene-01", "evolution": "The lobby arrow cannot point cleanly through the history"}, {"scene_id": "scene-06", "evolution": "Amuro's guidance repairs the visual path toward warm light"}]},
        {"id": "names-on-glass", "element": "Victory labels reflected over memorial names", "appearances": [{"scene_id": "scene-03", "evolution": "Odessa victory is experienced through Ryu and Matilda"}, {"scene_id": "scene-05", "evolution": "Solomon and Lalah dim the victory lamp"}, {"scene_id": "scene-06", "evolution": "Witness replaces verdict at the exit"}]},
    ]
    base["continuity_ledger"] = {
        "initial_states": [{"id": "story-time", "type": "time", "state": "Twenty minutes before museum closing"}, {"id": "primary-location", "type": "location", "state": "The exit arrow is broken and the final gallery is dark"}, {"id": "docent-relationship", "type": "relationship", "state": "RX and Zaku occupy opposing hero/villain labels"}],
        "events": [{"id": "shared-witness", "scene_id": "scene-06", "entity_id": "docent-relationship", "before": "RX and Zaku occupy opposing hero/villain labels", "after": "RX and Zaku share the role of witness", "evidence": "They remove both badges and hang WITNESS between them"}, {"id": "exit-repaired", "scene_id": "scene-06", "entity_id": "primary-location", "before": "The exit arrow is broken and the final gallery is dark", "after": "The exit path points through warm light", "evidence": "Amuro and the crew's mutual guidance resolves the gallery path"}, {"id": "clock-zero", "scene_id": "scene-06", "entity_id": "story-time", "before": "Twenty minutes before museum closing", "after": "Closing time, held until the group is together", "evidence": "The museum clock reaches zero and waits"}],
        "final_states": [{"entity_id": "story-time", "state": "Closing time, held until the group is together"}, {"entity_id": "primary-location", "state": "The exit path points through warm light"}, {"entity_id": "docent-relationship", "state": "RX and Zaku share the role of witness"}],
    }
    base["soundtrack_bible"] = {
        "enabled": True,
        "release_mode": "wonderswan-adaptation",
        "adaptation_project": "games/mobile-suit-gundam-summary/projects/mobile-suit-gundam-summary.wscvn.json",
        "master_motif": {
            "hook": "D-F-A-G archive-call figure",
            "interval_shape": "up a minor third, up a major third, down a major second",
            "tonal_center": "D minor with modal warmth",
            "meter": "4/4",
        },
        "motifs": [
            {
                "id": "archive-call",
                "subject": "The same history changing meaning when people replace spectacle",
                "hook": "D-F-A-G",
                "transformation_rule": "Thin, reorder, reharmonize, or change register without losing the four-note contour",
                "emotional_function": "Connect comic museum duty, military causality, grief, discovery, and home",
            }
        ],
        "cues": [
            {
                "id": "last-tour",
                "adaptation_track_id": "track_last_tour",
                "scene_ids": ["scene-01"],
                "motif_ids": ["archive-call"],
                "purpose": "Welcome the last tour and establish the closing clock without rushing the prose",
                "mood": "curious, hushed, warmly mechanical",
                "bpm": 58,
                "meter": "4/4",
                "tonal_center": "D minor",
                "hook": "D-F-A-G with long rests",
                "loop_bars": 12,
                "channel_roles": {"1": "soft sine lead", "2": "reserved PCM museum objects", "3": "triangle bass", "4": "sparse square clock glint"},
                "ws_feature": "192-step low-density tracker form with a reserved PCM lane",
                "mono_safe": True,
                "approval_status": "technical-preview",
                "reviewer": "Automated render and SwanSong QA; human listening pending",
            },
            {
                "id": "war-map",
                "adaptation_track_id": "track_war_map",
                "scene_ids": ["scene-01", "scene-02", "scene-04"],
                "motif_ids": ["archive-call"],
                "purpose": "Carry pursuit, command pressure, and military causality without becoming a victory march",
                "mood": "measured urgency and strategic tension",
                "bpm": 84,
                "meter": "4/4",
                "tonal_center": "D minor",
                "hook": "D-F-A-G in a firmer square voice",
                "loop_bars": 12,
                "channel_roles": {"1": "low square lead", "2": "reserved PCM museum objects", "3": "triangle bass motion", "4": "quiet map pulse"},
                "ws_feature": "register-separated three-voice arrangement",
                "mono_safe": True,
                "approval_status": "technical-preview",
                "reviewer": "Automated render and SwanSong QA; human listening pending",
            },
            {
                "id": "white-base",
                "adaptation_track_id": "track_white_base",
                "scene_ids": ["scene-01", "scene-02", "scene-04"],
                "motif_ids": ["archive-call"],
                "purpose": "Keep White Base's improvised people ahead of the machine spectacle",
                "mood": "forward motion with human warmth",
                "bpm": 72,
                "meter": "4/4",
                "tonal_center": "D minor",
                "hook": "D-F-A-G answered in a higher register",
                "loop_bars": 12,
                "channel_roles": {"1": "rounded sine lead", "2": "reserved PCM museum objects", "3": "triangle crew pulse", "4": "soft square response"},
                "ws_feature": "motif variation with internal A and B sections",
                "mono_safe": True,
                "approval_status": "technical-preview",
                "reviewer": "Automated render and SwanSong QA; human listening pending",
            },
            {
                "id": "archive-threshold",
                "adaptation_track_id": "track_archive_threshold",
                "scene_ids": ["scene-02", "scene-04", "scene-05"],
                "motif_ids": ["archive-call"],
                "purpose": "Mark new galleries, discoveries, and the widening idea of Newtype connection",
                "mood": "still wonder with an unsettled edge",
                "bpm": 64,
                "meter": "4/4",
                "tonal_center": "D minor",
                "hook": "D-F-A-G broken across open space",
                "loop_bars": 12,
                "channel_roles": {"1": "spaced sine fragments", "2": "reserved PCM museum objects", "3": "slow triangle threshold", "4": "single square glints"},
                "ws_feature": "long rests and a slowly opening register",
                "mono_safe": True,
                "approval_status": "technical-preview",
                "reviewer": "Automated render and SwanSong QA; human listening pending",
            },
            {
                "id": "memorial",
                "adaptation_track_id": "track_memorial",
                "scene_ids": ["scene-03", "scene-05"],
                "motif_ids": ["archive-call"],
                "purpose": "Let every apparent victory retain grief and specific names",
                "mood": "restrained memorial without sentimentality",
                "bpm": 52,
                "meter": "4/4",
                "tonal_center": "D minor",
                "hook": "F-A-G-F before the archive call returns",
                "loop_bars": 12,
                "channel_roles": {"1": "slow sine remembrance", "2": "reserved PCM memorial glass", "3": "triangle lament bass", "4": "rare square reflection"},
                "ws_feature": "widest loop and sparsest accent pattern",
                "mono_safe": True,
                "approval_status": "technical-preview",
                "reviewer": "Automated render and SwanSong QA; human listening pending",
            },
            {
                "id": "names-carried",
                "adaptation_track_id": "track_names_carried",
                "scene_ids": ["scene-06"],
                "motif_ids": ["archive-call"],
                "purpose": "Resolve the people-focused ending through names, witness, and a path home",
                "mood": "warm, earned, quietly expansive",
                "bpm": 58,
                "meter": "4/4",
                "tonal_center": "D minor resolving toward F major",
                "hook": "D-F-A-G rising into a homeward answer",
                "loop_bars": 12,
                "channel_roles": {"1": "warm sine return", "2": "reserved PCM exit objects", "3": "triangle home cadence", "4": "open square answer"},
                "ws_feature": "ending-specific register and cadence transformation",
                "mono_safe": True,
                "approval_status": "technical-preview",
                "reviewer": "Automated render and SwanSong QA; human listening pending",
            },
            {
                "id": "power-reckoning",
                "adaptation_track_id": "track_power_reckoning",
                "scene_ids": ["scene-06"],
                "motif_ids": ["archive-call"],
                "purpose": "Resolve the power-focused ending without turning machinery into the victor",
                "mood": "clear-eyed motion with unresolved weight",
                "bpm": 68,
                "meter": "4/4",
                "tonal_center": "D minor",
                "hook": "D-F-A-G carried by a firmer triangle lead",
                "loop_bars": 12,
                "channel_roles": {"1": "triangle reckoning lead", "2": "reserved PCM exit objects", "3": "low triangle foundation", "4": "measured square machinery pulse"},
                "ws_feature": "ending-specific timbre and cadence transformation",
                "mono_safe": True,
                "approval_status": "technical-preview",
                "reviewer": "Automated render and SwanSong QA; human listening pending",
            },
        ],
        "design_note": "Seven long, low-density arrangements transform one motif at narrative pivots. Intentional rests create breathing room; total silence is not the default. WonderSwan channel 2 remains reserved for the eight object-specific PCM effects.",
    }
    base["delight"] = {
        "signature_moments": [
            {"id": "delight-01", "chapter_id": "chapter-01", "scene_id": "scene-01", "type": "Comic contract", "setup": "A One Year War tour has twenty minutes", "delivery": "The clock advances out of professional concern while Zaku arrives under footnotes", "reader_effect": "The impossible compression feels playful but accountable", "only_here_reason": "Tiny robot docents make scale itself the joke"},
            {"id": "delight-02", "chapter_id": "chapter-01", "scene_id": "scene-04", "type": "Tender exhibit correction", "setup": "Miharu is represented as a red spy token", "delivery": "The token becomes an empty chair and lunch tins for her siblings", "reader_effect": "Abstraction gives way to one specific life", "only_here_reason": "Museum curation becomes character action"},
            {"id": "delight-03", "chapter_id": "chapter-01", "scene_id": "scene-06", "type": "Thematic visual payoff", "setup": "Broken exit, blank ticket, and faction badges", "delivery": "HOME, WITNESS, and the warm repaired path arrive together", "reader_effect": "The summary ends in relationship rather than machinery", "only_here_reason": "Every framing prop resolves through Escape"},
        ],
        "rhythm": [
            {"scene_id": "scene-01", "tension": 3, "warmth": 2, "humor": 4, "wonder": 4, "dominant_beat": "Refugee reframing", "reader_effect": "Fast orientation with moral clarity", "entry_hook": "The last tour before closing", "exit_pull": "The ship is whoever survived"},
            {"scene_id": "scene-02", "tension": 4, "warmth": 3, "humor": 3, "wonder": 2, "dominant_beat": "Crew and betrayal", "reader_effect": "Personal choices become strategic causes", "entry_hook": "Protocol arrests the survivors", "exit_pull": "Ral inherits the hunt"},
            {"scene_id": "scene-03", "tension": 5, "warmth": 2, "humor": 1, "wonder": 2, "dominant_beat": "Cost of growth", "reader_effect": "Victory refuses clean triumph", "entry_hook": "Amuro believes he can solve the mine alone", "exit_pull": "Names replace statistics"},
            {"scene_id": "scene-04", "tension": 4, "warmth": 4, "humor": 3, "wonder": 2, "dominant_beat": "Chosen return", "reader_effect": "Home and institutional use become simultaneous", "entry_hook": "Kai tries detachment", "exit_pull": "Amuro's skill flashes danger"},
            {"scene_id": "scene-05", "tension": 5, "warmth": 2, "humor": 1, "wonder": 5, "dominant_beat": "Connection weaponized", "reader_effect": "Awe turns to grief and blame", "entry_hook": "Newtypes may perceive one another", "exit_pull": "Two circles fail to overlap"},
            {"scene_id": "scene-06", "tension": 4, "warmth": 5, "humor": 2, "wonder": 4, "dominant_beat": "Mutual guidance home", "reader_effect": "Earned relief without a clean-war verdict", "entry_hook": "Command destroys itself", "exit_pull": "The clock waits for everyone"},
        ],
    }
    visual = base["illustration_bible"]
    visual["visual_contract"] = {"style": "Cozy hand-painted anime museum environments with faithful mechanical SD docents", "palette": "Museum navy, brass, Federation white/blue/red, Zaku olive, memorial burgundy, sunrise cream", "lighting": "Closing-time pools of warm light resolve into the bright A Baoa Qu exit", "character_consistency": "RX-78-2 and Zaku II remain fully mechanical, super-deformed, and faithful in silhouette", "forbidden_shortcuts": ["No procedural pictorial art", "No broad face bars", "No generated readable lettering", "No humanized robot faces"]}
    visual["character_designs"] = [
        {"character_id": "protagonist", "name": "Docent RX", "silhouette": "Oversized RX-78-2 helmet and V-fin over compact white armored body", "face_hair": "Mechanical eye cavities, red chin sensor, no human face or hair", "wardrobe": "Canonical armor colors; no clothing", "acting_range": "Open presenting hand, ticket-punch precision, eye and chin sensor pulse"},
        {"character_id": "foil", "name": "Docent Zaku", "silhouette": "Rounded olive helmet, mono-eye visor, right shield, left shoulder spikes, compact hose-lined body", "face_hair": "Single mechanical mono-eye, no human face or hair", "wardrobe": "Canonical olive armor with museum pointer", "acting_range": "Pointer corrections, open contextualizing hand, mono-eye sweep and blink"},
    ]
    visual["locations"] = [{"id": "location-01", "name": "Universal Century History Museum", "anchors": ["closing clock", "blank arrows", "campaign map", "Zabi board", "memorial glass", "sunrise exit"], "mood_range": "Comic closing duty, strategic clarity, memorial stillness, and warm release"}]
    visual["recurring_props"] = [{"id": "prop-01", "name": "Punched tour ticket", "continuity_rule": "Begin blank, accumulate causal stops, end with HOME"}]
    visual["moments"] = [
        {"id": "illustration-01", "scene_id": "scene-01", "role": "cover", "source_method": "imagegen", "prompt_status": "approved", "narrative_purpose": "Promise the entire museum frame and opposing docents", "emotional_beat": "The last tour begins under impossible time pressure", "composition": "Earth-and-colony atrium with dark title field and paired mechanical exhibit shapes", "must_show": ["closing museum", "Earth", "colony silhouettes", "room for title"], "must_avoid": ["series logo", "readable generated text", "human pilots"], "continuity_refs": ["protagonist", "foil", "location-01"], "status": "approved-runtime-master", "asset_path": "games/mobile-suit-gundam-summary/assets/sources/background_title_imagegen_v1.png"},
        {"id": "illustration-02", "scene_id": "scene-01", "role": "interior", "source_method": "imagegen", "prompt_status": "approved", "narrative_purpose": "Establish the closing-clock comic engine and footnote cart", "emotional_beat": "The museum itself appears worried about the deadline", "composition": "Closing-time lobby with clock, blank arrows, and footnote cart", "must_show": ["clock", "blank arrows", "footnote cart"], "must_avoid": ["readable generated text", "human visitors"], "continuity_refs": ["location-01"], "status": "approved-runtime-master", "asset_path": "games/mobile-suit-gundam-summary/assets/sources/background_main_imagegen_v1.png"},
        {"id": "illustration-03", "scene_id": "scene-06", "role": "interior", "source_method": "imagegen", "prompt_status": "approved", "narrative_purpose": "Show command networks collapsing into tangled arrows", "emotional_beat": "Concentrated power destroys itself", "composition": "Campaign map gallery and family-command board", "must_show": ["route map", "command portraits", "tangled connections"], "must_avoid": ["readable generated text", "victory iconography"], "continuity_refs": ["location-01"], "status": "approved-runtime-master", "asset_path": "games/mobile-suit-gundam-summary/assets/sources/background_ending_a_imagegen_v1.png"},
        {"id": "illustration-04", "scene_id": "scene-06", "role": "interior", "source_method": "imagegen", "prompt_status": "approved", "narrative_purpose": "Resolve fortress destruction into a human-scale route home", "emotional_beat": "Mutual guidance survives the machines", "composition": "Broken fortress behind glass with luminous path to sunrise door", "must_show": ["wreckage", "warm exit path", "small escape craft"], "must_avoid": ["battle screenshot recreation", "readable generated text", "victory pose"], "continuity_refs": ["location-01", "prop-01"], "status": "approved-runtime-master", "asset_path": "games/mobile-suit-gundam-summary/assets/sources/background_ending_b_imagegen_v1.png"},
        {"id": "illustration-05", "scene_id": "scene-01", "role": "interior", "source_method": "imagegen", "prompt_status": "approved", "narrative_purpose": "Make causality and optional context tangible through the visitor ticket", "emotional_beat": "One bright stop opens onto an intimidating route", "composition": "Brass ticket-punch station with a blank winding timeline and colored route lights", "must_show": ["ticket ribbon", "punch mechanism", "route lights"], "must_avoid": ["readable generated text", "literal episode list"], "continuity_refs": ["location-01", "prop-01"], "status": "planned-imagegen", "asset_path": "games/mobile-suit-gundam-summary/assets/sources/background_ticket_imagegen_v2.png"},
        {"id": "illustration-06", "scene_id": "scene-01", "role": "interior", "source_method": "imagegen", "prompt_status": "approved", "narrative_purpose": "Reframe the first Gundam launch as a civilian evacuation", "emotional_beat": "Spectacle dims until the ruined home remains", "composition": "Side 7 cutaway diorama with shelter lights, debris, and a distant white-red-blue mobile-suit silhouette", "must_show": ["colony cutaway", "shelter lights", "evacuation route"], "must_avoid": ["human portraits", "combat splash art", "readable generated text"], "continuity_refs": ["location-01"], "status": "planned-imagegen", "asset_path": "games/mobile-suit-gundam-summary/assets/sources/background_side7_imagegen_v2.png"},
        {"id": "illustration-07", "scene_id": "scene-02", "role": "interior", "source_method": "imagegen", "prompt_status": "approved", "narrative_purpose": "Keep White Base and its displaced crew as the causal spine", "emotional_beat": "An accidental refugee ship becomes a moving home", "composition": "Museum route table shaped by a white angular spacecraft and scattered civilian tokens", "must_show": ["ship route", "Earth curve", "civilian luggage tokens"], "must_avoid": ["readable generated text", "pilot portraits"], "continuity_refs": ["location-01"], "status": "planned-imagegen", "asset_path": "games/mobile-suit-gundam-summary/assets/sources/background_whitebase_imagegen_v2.png"},
        {"id": "illustration-08", "scene_id": "scene-03", "role": "interior", "source_method": "imagegen", "prompt_status": "approved", "narrative_purpose": "Hold Operation Odessa and its losses in one visual record", "emotional_beat": "The map advances only after the memorial breath", "composition": "Desert relief map beside unlit memorial glass and one restrained nuclear-warning glow", "must_show": ["desert map", "memorial glass", "dark victory lamp"], "must_avoid": ["explosion spectacle", "readable generated text"], "continuity_refs": ["location-01"], "status": "planned-imagegen", "asset_path": "games/mobile-suit-gundam-summary/assets/sources/background_odessa_imagegen_v2.png"},
        {"id": "illustration-09", "scene_id": "scene-04", "role": "interior", "source_method": "imagegen", "prompt_status": "approved", "narrative_purpose": "Replace Miharu's spy abstraction with the life she supported", "emotional_beat": "A token gives way to an empty chair and two lunch tins", "composition": "Quiet Belfast alcove with rain window, empty chair, two small lunch tins, and retired red token", "must_show": ["empty chair", "two lunch tins", "rain window"], "must_avoid": ["body depiction", "readable generated text", "melodramatic portrait"], "continuity_refs": ["location-01"], "status": "planned-imagegen", "asset_path": "games/mobile-suit-gundam-summary/assets/sources/background_miharu_imagegen_v2.png"},
        {"id": "illustration-10", "scene_id": "scene-04", "role": "interior", "source_method": "imagegen", "prompt_status": "approved", "narrative_purpose": "Show neutral Side 6 as fragile distance rather than safety", "emotional_beat": "Home is visible through glass but cannot be recovered", "composition": "Side 6 observation room with colony window, small domestic model room, and distant pursuit lights", "must_show": ["colony window", "domestic model room", "distant pursuit lights"], "must_avoid": ["human faces", "readable generated text"], "continuity_refs": ["location-01"], "status": "planned-imagegen", "asset_path": "games/mobile-suit-gundam-summary/assets/sources/background_side6_imagegen_v2.png"},
        {"id": "illustration-11", "scene_id": "scene-05", "role": "interior", "source_method": "imagegen", "prompt_status": "approved", "narrative_purpose": "Keep Solomon's strategic result and empty crew station simultaneously visible", "emotional_beat": "The captured-fortress lamp notices who is missing", "composition": "Asteroid-fortress museum model beside one empty bridge station and a dim victory light", "must_show": ["fortress model", "empty station", "dim victory lamp"], "must_avoid": ["victory pose", "readable generated text"], "continuity_refs": ["location-01"], "status": "planned-imagegen", "asset_path": "games/mobile-suit-gundam-summary/assets/sources/background_solomon_imagegen_v2.png"},
        {"id": "illustration-12", "scene_id": "scene-06", "role": "interior", "source_method": "imagegen", "prompt_status": "approved", "narrative_purpose": "Make the Zabi command chain legible without a genealogy lecture", "emotional_beat": "The family at the center is severing its own arrows", "composition": "Fractured command board around a cold solar-ray lens and broken red route lines", "must_show": ["command medallions", "broken arrows", "cold lens"], "must_avoid": ["readable names", "human portraits", "laser spectacle"], "continuity_refs": ["location-01"], "status": "planned-imagegen", "asset_path": "games/mobile-suit-gundam-summary/assets/sources/background_solar_ray_imagegen_v2.png"},
        {"id": "illustration-13", "scene_id": "scene-06", "role": "interior", "source_method": "imagegen", "prompt_status": "approved", "narrative_purpose": "Give the people-focused route a complete visual sentence", "emotional_beat": "Every reflected name crosses the warm threshold", "composition": "Morning museum exit with paired small mechanical docent silhouettes holding the door and many abstract reflections", "must_show": ["open door", "paired docent silhouettes", "warm reflected lights"], "must_avoid": ["readable lettering", "human faces", "victory salute"], "continuity_refs": ["protagonist", "foil", "location-01", "prop-01"], "status": "planned-imagegen", "asset_path": "games/mobile-suit-gundam-summary/assets/sources/background_home_people_imagegen_v2.png"},
        {"id": "illustration-14", "scene_id": "scene-06", "role": "interior", "source_method": "imagegen", "prompt_status": "approved", "narrative_purpose": "Give the power-focused route a sober but forward-moving final image", "emotional_beat": "The command arrows go dark while one witness path remains", "composition": "Darkened campaign floor with extinguished arrows and a single gold path beyond silent machines", "must_show": ["dark arrows", "gold path", "quiet machine exhibits"], "must_avoid": ["readable lettering", "weapon triumph", "human faces"], "continuity_refs": ["location-01"], "status": "planned-imagegen", "asset_path": "games/mobile-suit-gundam-summary/assets/sources/background_home_power_imagegen_v2.png"},
    ]
    for moment in visual["moments"]:
        asset_path = ROOT / str(moment["asset_path"])
        if asset_path.is_file():
            moment["asset_sha256"] = sha256(asset_path)
            moment["status"] = "approved-runtime-master"
            moment["approval_status"] = "pending-human-review"
    base["publication"].update(
        {
            "author": "SwanSong Story Forge",
            "subtitle": "Last Tour Before Closing",
            "rights": "Unofficial noncommercial transformative work; franchise rights remain with their respective owners",
            "identifier": "mobile-suit-gundam-summary-private-candidate-1",
            "cover_copy": "Two tiny docents. One year of war. Twenty minutes before closing.",
            "front_matter": ["Complete spoilers. Original commentary, independently generated art, and sound effects. Private/noncommercial lane."],
            "back_matter": ["Research and production evidence are preserved with the game source."],
        }
    )
    base["publication"]["cover"] = {
        "illustration_id": "illustration-01",
        "asset_path": "games/mobile-suit-gundam-summary/assets/sources/background_title_imagegen_v1.png",
        "asset_sha256": sha256(ROOT / "games/mobile-suit-gundam-summary/assets/sources/background_title_imagegen_v1.png"),
        "alt_text": "A dark museum atrium opens toward Earth and space-colony exhibits, leaving room for the closing-time tour title.",
    }
    base["editorial"] = {
        "reviewed_manuscript_sha256": "",
        "passes": [],
        "analysis_reports": [],
        "scene_delivery_reviews": [],
        "revision_ledger": [],
        "scorecard": [],
        "reader_tests": [],
        "reader_feedback_synthesis": {
            "reviewer": "",
            "manuscript_sha256": "",
            "consensus": [],
            "meaningful_disagreements": [],
            "genre_expectations": [],
            "confusion_patterns": [],
            "delight_patterns": [],
            "revision_decisions": [],
            "intentionally_not_changed": [],
        },
        "catalog_originality_review": {
            "status": "pending",
            "reviewer": "",
            "manuscript_sha256": "",
            "report_path": "reports/catalog-originality-report.json",
            "report_sha256": "",
            "findings": [],
            "decision": "",
        },
        "release_approval": {
            "status": "pending",
            "reviewer": "",
            "manuscript_sha256": "",
            "statement": "Human story and public-release review have not been performed.",
        },
    }
    base["quality"].update(
        {
            "minimum_premise_candidates": 5,
            "minimum_scenes": 6,
            "minimum_setups": 8,
            "minimum_motifs": 2,
            "minimum_scene_words": 200,
            "maximum_scene_words": 800,
            "minimum_draft_completion_ratio": 1.0,
            "minimum_signature_moments_per_chapter": 3,
            "maximum_flat_rhythm_run": 2,
            "minimum_voice_samples_per_character": 2,
            "minimum_illustration_moments": 14,
        }
    )
    return base, [(scene, group["node_ids"]) for scene, group in zip(scenes, groups, strict=True)]


def build_manuscript(scene_groups: list[tuple[dict, list[str]]], spec: dict) -> str:
    nodes = {str(node["id"]): node for node in spec["nodes"]}
    lines = ["# Last Tour Before Closing", "", "A preferred-route source manuscript for the branching visual novel.", ""]
    for scene, node_ids in scene_groups:
        lines.extend([f"<!-- scene: {scene['id']} -->", "", f"## {scene['specific_image']}", ""])
        for node_id in node_ids:
            node = nodes[node_id]
            speaker = str(node.get("speaker") or "Museum")
            voice = "protagonist" if speaker == "Docent RX" else "foil"
            lines.extend([f"<!-- voice: {voice} -->", "", f"**{speaker}:** {authored_text(node)}", ""])
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    spec = json.loads(GAME_SPEC.read_text(encoding="utf-8"))
    manifest, scene_groups = build_manifest(spec)
    manuscript = build_manuscript(scene_groups, spec)
    serialized = json.dumps(manifest, ensure_ascii=False)
    forbidden = [token for token in ("TODO", "Mara", "Teo", "tea kiosk", "A finished, concrete") if token in serialized]
    if forbidden:
        raise RuntimeError(f"Stale fixture text remained in narrative manifest: {forbidden}")
    (PROJECT_ROOT / "manuscript").mkdir(parents=True, exist_ok=True)
    (PROJECT_ROOT / "novel.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (PROJECT_ROOT / "manuscript" / "chapter-01.md").write_text(manuscript, encoding="utf-8")
    print(f"Wrote {PROJECT_ROOT / 'novel.json'}")
    print(f"Wrote {PROJECT_ROOT / 'manuscript' / 'chapter-01.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
