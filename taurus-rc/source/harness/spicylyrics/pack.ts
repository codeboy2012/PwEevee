// Packs test documents with Spicy Lyrics' own packer, so the ObjC decoder is checked against the
// only implementation of this shape there is. The words are placeholders, not anyone's lyrics.
import { SLObjPack } from "./build/spicy-lyrics/src/utils/objpack.ts";
const packer = new SLObjPack();

const syllable = {
  Type: "Syllable",
  SongWriters: ["A Writer"],
  Content: [
    {
      Type: "Vocal",
      Lead: {
        StartTime: 1.5, EndTime: 4.25,
        Syllables: [
          { Text: "al", StartTime: 1.5, EndTime: 1.9, IsPartOfWord: true },
          { Text: "pha", StartTime: 1.9, EndTime: 2.4 },
          { Text: "bravo", StartTime: 2.6, EndTime: 4.25 },
        ],
      },
      Background: [
        { StartTime: 3.0, EndTime: 4.0, Syllables: [{ Text: "echo", StartTime: 3.0, EndTime: 4.0 }] },
      ],
    },
    {
      Type: "Vocal",
      OppositeAligned: true,
      Lead: {
        StartTime: 9.0, EndTime: 11.0,
        Syllables: [{ Text: "charlie", StartTime: 9.0, EndTime: 11.0 }],
      },
    },
  ],
};

const line = {
  Type: "Line",
  Content: [
    { Type: "Vocal", Text: "delta foxtrot", StartTime: 2.0, EndTime: 4.0 },
    { Type: "Vocal", Text: "golf hotel", StartTime: 4.5, EndTime: 6.0 },
  ],
};

const staticDoc = { Type: "Static", Lines: [{ Text: "india" }, { Text: "" }, { Text: "juliett" }] };

const out = {
  syllable: packer.pack(syllable),
  line: packer.pack(line),
  static: packer.pack(staticDoc),
  // Round-trip proof that the packer and its unpacker agree on these documents.
  roundTrips: [syllable, line, staticDoc].every(
    (d) => JSON.stringify(packer.unpack(packer.pack(d))) === JSON.stringify(d)
  ),
};
console.log(JSON.stringify(out));
