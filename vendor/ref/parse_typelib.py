# -*- coding: utf-8 -*-
"""Parse dl_library.dl_typelib (LTLD format) into JSON: types with member offsets."""
import struct, json, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))

def dlsum(name):
    r = 5381
    for ch in name:
        r = (r * 33 + ord(ch)) & 0xFFFFFFFF
    return (r - 5381) & 0xFFFFFFFF

def load_names():
    names = {}
    for line in open(os.path.join(HERE, "dl_type_names.txt"), encoding="utf-8", errors="replace"):
        t = line.strip()
        if not t or t.startswith("//"):
            continue
        names[dlsum(t)] = t
    return names

def parse(path):
    data = open(path, "rb").read()
    names = load_names()
    assert data[0:4] == b"LTLD"
    (version,) = struct.unpack_from("<I", data, 4)
    (type_count, enum_count, member_count, ev_count, ea_count,
     def_size, str_size) = struct.unpack_from("<7I", data, 8)
    print("version=%d types=%d enums=%d members=%d evalues=%d ealias=%d defsize=%d strsize=%d filesize=%d"
          % (version, type_count, enum_count, member_count, ev_count, ea_count, def_size, str_size, len(data)),
          file=sys.stderr)
    off = 36
    type_hashes = struct.unpack_from("<%dI" % type_count, data, off); off += 4 * type_count
    enum_hashes = struct.unpack_from("<%dI" % enum_count, data, off); off += 4 * enum_count
    # rawDLTypeDesc = 36 bytes
    type_descs = []
    for i in range(type_count):
        (name_off, flags, size32, size64, align32, align64, mcount, mstart, comment_off) = struct.unpack_from("<9I", data, off)
        type_descs.append(dict(name_off=name_off, flags=flags, size=size64, align=align64,
                               member_count=mcount, member_start=mstart, comment_off=comment_off))
        off += 36
    # rawDLEnumDesc = 32 bytes
    enum_descs = []
    for i in range(enum_count):
        (name_off, flags, storage, vcount, vstart, acount, astart, comment_off) = struct.unpack_from("<IIB3xIIIII", data, off)
        enum_descs.append(dict(name_off=name_off, flags=flags, storage=storage,
                               value_count=vcount, value_start=vstart, alias_count=acount,
                               alias_start=astart, comment_off=comment_off))
        off += 32
    # rawDLMemberDesc = 72 bytes (TypeID is u32)
    member_descs = []
    for i in range(member_count):
        (name_off, comment_off, unknown_off, atom, storage, union_bf, type_id,
         size32, size64, align32, align64, off32, off64, dvo, dvs, flags) = struct.unpack_from(
            "<IIIBBHI9I", data, off)
        member_descs.append(dict(name_off=name_off, comment_off=comment_off, unknown_off=unknown_off,
                                 atom=atom, storage=storage, union_bf=union_bf,
                                 type_id=type_id,
                                 size=size64, align=align64, offset=off64,
                                 default_value_offset=dvo, default_value_size=dvs, flags=flags))
        off += 72
    # rawDLEnumValueDesc = 16, rawDLEnumAliasDesc = 8
    enum_values = []
    for i in range(ev_count):
        (main_alias, comment_off, value) = struct.unpack_from("<IIQ", data, off)
        enum_values.append(dict(main_alias=main_alias, comment_off=comment_off, value=value))
        off += 16
    enum_aliases = []
    for i in range(ea_count):
        (name_off, value_index) = struct.unpack_from("<II", data, off)
        enum_aliases.append(dict(name_off=name_off, value_index=value_index))
        off += 8
    default_data = data[off:off + def_size]; off += def_size
    strings_data = data[off:off + str_size]; off += str_size
    print("parsed to offset %d of %d (remaining %d)" % (off, len(data), len(data) - off), file=sys.stderr)

    def cstr(base, o):
        if o == 0xFFFFFFFF or not base:
            return ""
        end = base.find(b"\x00", o)
        if end < 0:
            return ""
        return base[o:end].decode("utf-8", "replace")

    types = {}
    for i, td in enumerate(type_descs):
        h = type_hashes[i]
        name = names.get(h, "0x%08X" % h)
        t = dict(name=name, hash=h, size=td["size"], align=td["align"],
                 flags=td["flags"], members=[])
        for k in range(td["member_count"]):
            if td["member_start"] + k >= len(member_descs):
                print("WARN: member idx out of range for type %s (start=%d count=%d)" % (name, td["member_start"], td["member_count"]), file=sys.stderr)
                break
            md = member_descs[td["member_start"] + k]
            mname = cstr(strings_data, md["name_off"])
            if not mname:
                mname = "m%d" % k
            t["members"].append(dict(name=mname, offset=md["offset"], size=md["size"],
                                     atom=md["atom"], storage=md["storage"],
                                     union_bf=md["union_bf"], type_id=md["type_id"],
                                     flags=md["flags"]))
        types[name] = t
    enums = {}
    for i, ed in enumerate(enum_descs):
        h = enum_hashes[i]
        name = names.get(h, "0x%08X" % h)
        vals = []
        for k in range(ed["value_count"]):
            if ed["value_start"] + k >= len(enum_values):
                break
            vd = enum_values[ed["value_start"] + k]
            vname = ""
            if vd["main_alias"] != 0xFFFFFFFF and ed["alias_start"] + vd["main_alias"] < len(enum_aliases):
                ad = enum_aliases[ed["alias_start"] + vd["main_alias"]]
                vname = cstr(strings_data, ad["name_off"])
            vals.append(dict(name=vname or ("v%d" % k), value=vd["value"]))
        enums[name] = vals
    return types, enums

if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "dl_library.dl_typelib")
    types, enums = parse(src)
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "typelib_all.json")
    json.dump(types, open(out, "w", encoding="utf-8"))
    json.dump(enums, open(out + ".enums", "w", encoding="utf-8"))
    print("dumped %d types, %d enums -> %s" % (len(types), len(enums), out), file=sys.stderr)
