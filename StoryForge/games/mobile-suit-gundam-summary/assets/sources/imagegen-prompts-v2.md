# ImageGen production record — v2 experience pass

This pass expands the museum from four repeated rooms to a visual sequence of
fourteen distinct exhibits and adds two acting poses. Every new pictorial
master must come from built-in ImageGen. Local code may only crop, resize,
quantize, preserve alpha, derive body-locked mechanical blinks, and assemble
review evidence.

The existing closing-time lobby is the environment style reference: richly
painted late-1970s anime museum architecture, warm brass light against deep
navy and burgundy, clean silhouettes, no readable generated lettering, and
strong shapes that survive reduction to 224×144. All environments reserve a
quiet lower band for the runtime dialogue box and avoid important detail at the
far left or right where a docent sprite may stand.

## Punched timeline

Source: `background_ticket_imagegen_v2.png`

> Using the supplied museum lobby only as a visual style reference, create a
> new wide 16:9 hand-painted anime museum exhibit after closing. A brass
> ticket-punch station unspools one cream paper ribbon through seven abstract
> colored route lights; the first stop is punched and glowing, the remaining
> stops are blank shapes without letters. Include a small mechanical punch,
> glass rail, deep navy walls, burgundy floor, and warm brass pools of light.
> Clear visual hierarchy, quiet lower dialogue band, open sprite space on both
> sides, readable at 224×144. No characters, no humans, no numbers, no words,
> no logos, no watermark, no episode list, no UI.

## Side 7 refugee diorama

Source: `background_side7_imagegen_v2.png`

> Using the supplied museum lobby only as a visual style reference, create a
> new wide 16:9 hand-painted anime museum diorama of a damaged cylindrical
> space colony cutaway. Tiny shelter lights and a clear evacuation path lead
> toward an angular white spacecraft; debris and extinguished homes dominate
> while a distant white, blue, red, and yellow humanoid mobile-suit silhouette
> is only one exhibit element. Somber navy, warm shelter amber, brass display
> rail, quiet lower dialogue band, open sprite space, readable at 224×144. No
> visible people, no portraits, no readable text, no logos, no watermark, no
> triumphant combat splash composition.

## White Base route table

Source: `background_whitebase_imagegen_v2.png`

> Using the supplied museum lobby only as a visual style reference, create a
> new wide 16:9 hand-painted anime museum route table. A raised white angular
> spacecraft model travels from a damaged colony toward the blue curve of
> Earth and back into space. Small luggage, blanket, toolbox, and meal-tin
> tokens make the route feel carried by displaced civilians rather than by a
> weapon. Brass edge lights, dark teal room, burgundy accents, quiet lower
> dialogue band, open sprite space, readable at 224×144. No people, no faces,
> no readable labels, no logos, no watermark, no UI.

## Odessa memorial

Source: `background_odessa_imagegen_v2.png`

> Using the supplied museum lobby only as a visual style reference, create a
> new wide 16:9 hand-painted anime museum room combining a desert relief map
> with tall unlit memorial glass. A restrained red warning glow sits under a
> glass cover, while a victory lamp remains deliberately dark. Wind-shaped
> sand contours, brass rails, deep burgundy and navy, one respectful warm edge
> light, quiet lower dialogue band, open sprite space, readable at 224×144.
> No explosion spectacle, no bodies, no portraits, no readable text, no logos,
> no watermark, no UI.

## Miharu's empty chair

Source: `background_miharu_imagegen_v2.png`

> Using the supplied museum lobby only as a visual style reference, create a
> new wide 16:9 quiet Belfast museum alcove at night. Rain traces a tall window.
> The focal exhibit is one empty modest chair beside two small metal lunch tins
> and a retired red game-piece token under glass. The scene feels specific,
> tender, and restrained rather than sentimental. Dark teal, wet blue, warm
> brass edge light, burgundy floor, quiet lower dialogue band, open sprite
> space, readable at 224×144. No person, no body, no portrait, no readable
> text, no logos, no watermark, no UI.

## Side 6 window

Source: `background_side6_imagegen_v2.png`

> Using the supplied museum lobby only as a visual style reference, create a
> new wide 16:9 hand-painted anime observation gallery inside a neutral space
> colony. A huge window shows the curved colony interior and a fragile blue
> domestic glow. A small model room with an untouched workbench sits behind
> glass, while distant red and white pursuit lights approach outside. Home is
> visible but unreachable. Navy, cool cyan, restrained brass, quiet lower
> dialogue band, open sprite space, readable at 224×144. No people, no faces,
> no readable text, no logos, no watermark, no UI.

## Solomon memorial

Source: `background_solomon_imagegen_v2.png`

> Using the supplied museum lobby only as a visual style reference, create a
> new wide 16:9 hand-painted anime museum exhibit. A craggy asteroid-fortress
> model hangs over a tactical table, but the emotional focal point is one
> empty bridge station and a victory lamp that has dimmed itself. A few
> abstract solar-mirror shapes sit behind glass without firing. Charcoal navy,
> muted brass, one pale memorial light, quiet lower dialogue band, open sprite
> space, readable at 224×144. No people, no portraits, no weapon triumph, no
> readable text, no logos, no watermark, no UI.

## Fractured command board

Source: `background_solar_ray_imagegen_v2.png`

> Using the supplied museum lobby only as a visual style reference, create a
> new wide 16:9 hand-painted anime museum command gallery. Abstract armored
> profile medallions form one family cluster around a cold circular
> solar-ray lens; red route arrows are snapping and folding back into the
> cluster. The board explains self-destruction through composition, without
> names or faces. Deep black-blue, wine red, cold white lens, sparse brass,
> quiet lower dialogue band, open sprite space, readable at 224×144. No human
> portraits, no readable text, no laser firing, no logos, no watermark, no UI.

## Every voice home

Source: `background_home_people_imagegen_v2.png`

> Using the supplied museum lobby only as a visual style reference, create a
> new wide 16:9 hand-painted anime ending image inside the museum at sunrise.
> An open door pours warm cream light across the floor. Two very small,
> fully mechanical super-deformed docent silhouettes—one white with a V-fin,
> one rounded olive with a single visor—hold opposite sides of the door.
> Many abstract name-like reflections cross the threshold as points and bands
> of light, never readable letters. A punched paper ticket glows near the path.
> Quiet lower dialogue band, readable at 224×144. No human faces, no victory
> salute, no readable text, no logos, no watermark, no UI.

## Witness beyond the map

Source: `background_home_power_imagegen_v2.png`

> Using the supplied museum lobby only as a visual style reference, create a
> new wide 16:9 sober hand-painted anime ending image. A dark campaign-map
> floor has many extinguished red and blue arrows. Silent mobile-suit exhibit
> silhouettes and a cold command lens recede into darkness, while one narrow
> gold path continues toward a distant morning doorway. The composition says
> machinery could not choose the way home. Quiet lower dialogue band, open
> sprite space, readable at 224×144. No people, no weapon triumph, no readable
> text, no logos, no watermark, no UI.

## Docent RX ticket pose

Raw ImageGen master: `docent-rx78-ticket-imagegen-v2.png`

Chroma-keyed production source:
`docent-rx78-ticket-cutout-imagegen-v2.png`

The first edit returned a baked transparency checkerboard and was rejected.
ImageGen then performed this recovery edit on that generated result before any
local conversion:

> Replace only the entire background with one perfectly flat, solid chroma-key
> magenta color. Preserve the robot, ticket, ticket punch, pose, scale, crop,
> lighting, colors, and every mechanical detail exactly. Do not add shadows,
> checkerboards, gradients, scenery, text, logos, or watermarks.

The accepted flat-background ImageGen result is the raw master named above.
Local tooling only removed that uniform key color and performed the documented
WonderSwan conversion.

> Edit the supplied Docent RX image. Preserve the exact faithful mechanical
> super-deformed RX-78-2 design, proportions, armor colors, V-fin, face,
> stance, lighting, cel-rendering style, and transparent background. Change
> only the arms and hands: the left hand presents a small blank cream museum
> ticket with one round punched hole, while the right hand holds a compact
> brass ticket punch near the waist. Keep the full body, feet, V-fin, ticket,
> and tool within frame with generous transparent margin. One character only.
> No human anatomy, no human eyes, no text, no logo, no watermark, no scenery,
> no weapon.

## Docent Zaku command-pointer pose

Raw ImageGen master: `docent-zaku-pointer-imagegen-v2.png`

Chroma-keyed production source:
`docent-zaku-pointer-cutout-imagegen-v2.png`

> Edit the supplied Docent Zaku image. Preserve the exact faithful mechanical
> super-deformed green MS-06 Zaku II design, proportions, rounded olive helmet,
> black mono-eye visor with one pink sensor, shoulder shield, shoulder spikes,
> hoses, stance, lighting, cel-rendering style, and transparent background.
> Change only the arms: the pointer hand extends the slim museum pointer
> diagonally toward an exhibit above and to the right, while the free hand
> holds a small folded blank command plaque at chest height. Keep the full
> body, feet, pointer, shoulder silhouette, and plaque within frame with
> generous transparent margin. One character only. No human anatomy, no
> readable text, no logo, no watermark, no scenery, no gun.

Exact SHA-256 hashes for accepted masters and runtime derivatives are recorded
in `../asset-provenance.json` after the build.
