# Reference Novel: The Last Tea Home

This is Story Forge's honest end-to-end walkthrough project. It contains a
complete six-scene original short novel and a deterministic builder for its
schema-v3 manifest. The builder runs the Story Room, visual map, scene context,
research, genre, ImageGen Art Room, music auditions, and WonderSwan adaptation
bridge.

It intentionally stops before reader, art, and release approval. Those gates
need real unprimed readers, actual ImageGen outputs reviewed as a set, and a
responsible human decision. The reference never fills those fields with fake
green evidence.

```bash
python3 examples/reference-novel/build_reference.py /tmp/story-forge-reference
open /tmp/story-forge-reference/workbench/story-map.html
```

The result passes the `draft` gate and demonstrates every automated workbench
surface that can be exercised without inventing a person or production asset.
Its WonderSwan file is a source-mapped authoring scaffold, not a finished game.

Production artwork is absent on purpose. When developing a real edition, use
ImageGen for the cover and every interior illustration, preserve the masters
and prompt history, and complete per-image plus full-set review.
