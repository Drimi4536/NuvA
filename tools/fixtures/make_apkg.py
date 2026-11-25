"""Тестовые колоды Anki для tests/test_all: python3 tools/fixtures/make_apkg.py
deck_v1.apkg — Lookupper-заметка со звуком и картинкой, 300 заметок Basic (много страниц), длинная заметка (переполнение);
deck_v2.apkg — те же guid: один перевод изменён, одна заметка новая (проверка «Обновить из Anki»);
deck_new.apkg — только collection.anki21b (новый формат — должна быть понятная ошибка)."""
import io, json, os, sqlite3, sys, tempfile, zipfile
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "tests", "fixtures")
SEP = "\x1f"
LK = ["Word", "DictionaryForm", "WordSound", "WordTranslation", "Image", "Context", "ContextTranslation", "Definition", "Ipa"]


def mp3_bytes():
    # короткий настоящий mp3 (тишина) — кадры MPEG-1 Layer III 128 кбит/с 44.1 кГц
    frame = bytes([0xFF, 0xFB, 0x90, 0x64]) + bytes(413)
    return frame * 40


def jpg_bytes():
    im = Image.new("RGB", (160, 90), (232, 121, 43))
    b = io.BytesIO()
    im.save(b, "JPEG")
    return b.getvalue()


def build(path, version):
    tmp = tempfile.mktemp(suffix=".db")
    c = sqlite3.connect(tmp)
    c.executescript("""
    CREATE TABLE [col]
    (
    	[id] integer primary key, [crt] integer not null, [mod] integer not null, [scm] integer not null,
    	[ver] integer not null, [dty] integer not null, [usn] integer not null, [ls] integer not null,
    	[conf] text not null, [models] text not null, [decks] text not null, [dconf] text not null, [tags] text not null
    );
    CREATE TABLE notes (id integer primary key, guid text not null, mid integer not null, mod integer not null,
      usn integer not null, tags text not null, flds text not null, sfld integer not null, csum integer not null,
      flags integer not null, data text not null);
    CREATE TABLE cards (id integer primary key, nid integer not null, did integer not null, ord integer not null,
      mod integer not null, usn integer not null, type integer not null, queue integer not null, due integer not null,
      ivl integer not null, factor integer not null, reps integer not null, lapses integer not null, left integer not null,
      odue integer not null, odid integer not null, flags integer not null, data text not null);
    CREATE TABLE revlog (id integer primary key, cid integer not null);
    CREATE INDEX ix_notes_csum on notes (csum);
    """)
    models = {
        "100": {"name": "Lookupper Flash v2.0", "flds": [{"name": n} for n in LK]},
        "200": {"name": "Basic", "flds": [{"name": "Front"}, {"name": "Back"}]},
    }
    decks = {"1": {"name": "Default"}, "10": {"name": "Lookupper::English"}, "20": {"name": "Big::Deck"}}
    c.execute("insert into col values (1,0,0,0,11,0,0,0,'{}',?,?,'{}','{}')", (json.dumps(models), json.dumps(decks)))
    nid = 1000
    def note(guid, mid, flds, did):
        nonlocal nid
        nid += 1
        c.execute("insert into notes values (?,?,?,0,0,'',?,'',0,0,'')", (nid, guid, int(mid), SEP.join(flds)))
        c.execute("insert into cards values (?,?,?,0,0,0,0,0,0,0,0,0,0,0,0,0,0,'')", (nid + 500000, nid, did))
    note("lk-walk", 100, ["walking", "walk", "[sound:walk.mp3]", "ходить", '<img src="walk.jpg" alt="">',
                          "Someone's <u>walking</u> in the attic.", "Кто-то <u>ходит</u> на чердаке.",
                          "передвигаться на ногах", "wɔk"], 10)
    note("lk-tea", 100, ["tea&nbsp;time", "", "", "время чая" if version == 1 else "время пить чай", "",
                         "It's <b>tea time</b>!<br>Come in.", "", "", ""], 10)
    for i in range(300):
        note("b%03d" % i, 200, ["word %03d" % i, "слово %03d" % i], 20)
    note("long", 200, ["long " + "very " * 2500 + "end", "длинная"], 20)
    if version == 2:
        note("lk-new", 100, ["arrived", "arrive", "", "прибыл", "", "", "", "", "əˈraɪv"], 10)
    c.commit()
    c.close()
    data = open(tmp, "rb").read()
    os.remove(tmp)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("collection.anki21", data)
        z.writestr("collection.anki2", data)
        z.writestr("0", mp3_bytes())
        z.writestr("1", jpg_bytes())
        z.writestr("media", json.dumps({"0": "walk.mp3", "1": "walk.jpg"}))


os.makedirs(OUT, exist_ok=True)
build(os.path.join(OUT, "deck_v1.apkg"), 1)
build(os.path.join(OUT, "deck_v2.apkg"), 2)
with zipfile.ZipFile(os.path.join(OUT, "deck_new.apkg"), "w") as z:
    z.writestr("collection.anki21b", b"\x28\xb5\x2f\xfd zstd")
    z.writestr("collection.anki2", b"stub")
print("ok")
