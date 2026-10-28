#!/usr/bin/env python3
"""Turns a TTML document into a fixture: every timing, voice, backing span, translation and
transliteration kept where it is, every word swapped for filler of the same script and length, and
the songwriters dropped, so the harness plays a song's shape without carrying its lyrics.

    ./anonymise.py song.ttml > fixture.ttml
"""
import re
import sys

LATIN = "loremipsumdolorsitametconsecteturadipiscingelitseddoeiusmodtemporincididunt"
KANA = "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわ"
HANGUL = "가나다라마바사아자차카타파하거너더러머버서어저처"
HAN = "一二三四五六七八九十百千万天地山川花風月"
HEBREW_ARABIC = "אבגדהוזחטיכלמנסעפצקרשת"

def swap(ch, i):
    code = ord(ch)
    if ch.isascii() and ch.isalpha():
        c = LATIN[i % len(LATIN)]
        return c.upper() if ch.isupper() else c
    if 0x3040 <= code < 0x3100:
        return KANA[i % len(KANA)]
    if 0xAC00 <= code < 0xD7A4:
        return HANGUL[i % len(HANGUL)]
    if 0x3400 <= code < 0xA000:
        return HAN[i % len(HAN)]
    if 0x0590 <= code < 0x0900:
        return HEBREW_ARABIC[i % len(HEBREW_ARABIC)]
    if ch.isalpha():
        return LATIN[i % len(LATIN)]
    return ch

def filler(text):
    """Each run of letters is swapped as a whole, seeded by the run itself, so a word reads the same
    filler wherever it comes: a pronunciation that spells a line out as itself still does."""
    def run(match):
        word = match.group(0)
        seed = sum(ord(c) * (k + 7) for k, c in enumerate(word.lower()))
        return "".join(swap(c, seed + k) for k, c in enumerate(word))
    return re.sub(r"[^\W\d_]+", run, text)

def main(path):
    xml = open(path, encoding="utf-8").read()
    xml = re.sub(r"<songwriters>.*?</songwriters>", "", xml, flags=re.S)
    # Text between tags only: the tags and their attributes stay exactly as they were.
    xml = re.sub(r">([^<]+)<", lambda m: ">" + filler(m.group(1)) + "<", xml)
    sys.stdout.write(xml)

if __name__ == "__main__":
    main(sys.argv[1])
