# Third-Party Licenses

XIVGamepad ports code and assets from **xivcrossbar**
(<https://github.com/AliekberFFXI/xivcrossbar>), a Windower 4 addon licensed under the MIT License,
Copyright (c) 2020 AliekberFFXI. Several of the ported files carry their own BSD 3-Clause license
headers from the projects they originated in. Those in-file headers are retained verbatim in this
repository and **remain authoritative for those files**; this document summarizes them and
reproduces each license text once.

## Ported files

| File in this repo                      | Origin (xivcrossbar path)            | Author(s)                                                    | License |
|----------------------------------------|--------------------------------------|--------------------------------------------------------------|---------|
| `crossbar/icon_extractor.lua`          | `ui/icon_extractor.lua`              | Rubenator (base extraction code by Trv of the Windower Discord) | BSD-3-Clause, Copyright (c) 2021, Rubenator |
| `crossbar/mountroulette.lua`           | `libs/mountroulette/mountroulette.lua` | Dean James (Xurion of Bismarck)                            | BSD-3-Clause, Copyright (c) 2020, Dean James (Xurion of Bismarck) |
| `crossbar/skillchain/skillchains.lua`  | `libs/skillchain/skillchains.lua`    | Ivaar                                                        | BSD-3-Clause, Copyright (c) 2017, Ivaar |
| `crossbar/skillchain/skills.lua`       | `libs/skillchain/skills.lua`         | Ivaar                                                        | BSD-3-Clause, Copyright (c) 2017, Ivaar |
| `crossbar/resource_generator.lua`      | `resource_generator.lua`             | Aliekber (AliekberFFXI)                                      | MIT (xivcrossbar repository license) |
| `crossbar/kebab_casify.lua`            | `libs/kebab_casify.lua`              | Aliekber (AliekberFFXI)                                      | MIT (xivcrossbar repository license) |
| `crossbar/ordered_pairs.lua`           | `libs/ordered_pairs.lua`             | Aliekber (AliekberFFXI)                                      | MIT (xivcrossbar repository license) |
| `crossbar/md5.lua`                     | `libs/md5.lua`                       | Enrique Garcia Cota + Adam Baldwin + hanzao + Equi 4 Software | MIT, Copyright (c) 2013 (md5.lua 1.1.0, <https://github.com/kikito/md5.lua>) |

Provenance notes, as recorded in the files' own headers:

- `icon_extractor.lua` (v1.1.2) is "Written by Rubenator of Leviathan" with "Base Extraction Code
  graciously provided by Trv of Windower discord"; its BSD header originates from Rubenator's
  EquipViewer addon.
- `mountroulette.lua` is based on the **Mount Roulette** addon (v3.0.1) by Dean James
  (Xurion of Bismarck).
- `skillchains.lua` and `skills.lua` are based on the **SkillChains** addon by Ivaar.
- `resource_generator.lua`, `kebab_casify.lua`, and `ordered_pairs.lua` carry no license header of
  their own; they are covered by the xivcrossbar repository MIT license reproduced below.
- xivcrossbar itself derives from **XIVHotbar** by SirEdeonX (Copyright (c) 2017, SirEdeonX,
  BSD-3-Clause).

## License texts

### BSD 3-Clause License

Applies to the files listed above with the following copyright lines:

- Copyright (c) 2017, Ivaar. All rights reserved.
  (`crossbar/skillchain/skillchains.lua`, `crossbar/skillchain/skills.lua`)
- Copyright (c) 2020, Dean James (Xurion of Bismarck). All rights reserved.
  (`crossbar/mountroulette.lua`)
- Copyright (c) 2021, Rubenator. All rights reserved.
  (`crossbar/icon_extractor.lua`)

In each file's retained header the third clause names the originating project (SkillChains,
Mount Roulette, and EquipViewer respectively) and the disclaimer names the copyright holder.

```
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.
* Neither the name of the project nor the
  names of its contributors may be used to endorse or promote products
  derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### MIT License (xivcrossbar)

Reproduced verbatim from the xivcrossbar repository `LICENSE` file:

```
MIT License

Copyright (c) 2020 AliekberFFXI

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### MIT License (md5.lua)

`crossbar/md5.lua` embeds the same standard MIT license text in its header (retained verbatim in
the file, where it remains authoritative), differing only in its copyright line:

```
Copyright (c) 2013 Enrique García Cota + Adam Baldwin + hanzao + Equi 4 Software
```

## Assets

`images/icons/abilities/`, `images/icons/spells/`, `images/icons/weapons/`,
`images/icons/elements/`, and `images/icons/skillchain/` are game icons extracted from
FINAL FANTASY XI, (c) SQUARE ENIX CO., LTD. All rights to that artwork remain with
SQUARE ENIX CO., LTD.; the icons are shipped here on the same basis on which xivcrossbar ships
them — as assets of a fan-made addon for use with the game they were extracted from, with no
ownership claimed.

`images/icons/iconpacks/default/` is original xivcrossbar icon-pack art by Aliekber
(AliekberFFXI), covered by the xivcrossbar MIT license reproduced above.
