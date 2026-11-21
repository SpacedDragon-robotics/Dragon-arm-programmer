"""Export the Dragon-Arm One CAD rig to the app's 3D view.

Run with Blender (the .blend is opened read-only and never saved):

  blender -b "D:/Claude/dragon-arm/dragon_arm_trailer.blend" -P tools/export_3d_model.py -- <work_dir> [ratio]

then convert the GLB it writes with balsam and copy the result into
content/view3d/rigs/ (tools/export_3d_model.ps1 does all three steps).

What it does
  * Every mesh is assigned to the kinematic link that moves it: the nearest
    PIVOT empty above it (ARM_ROOT = the fixed base).
  * Meshes are merged per (link, material) -- about 40 meshes instead of 450
    objects -- and re-expressed in that link's PIVOT frame, in millimetres.
  * Each merged mesh is decimated (CAD tessellation is far denser than a
    real-time view needs) and gets angle-based sharp edges for flat shading.
  * The rig QML is generated from the pivot transforms, so the hierarchy in
    the app is exactly the hierarchy in Blender: base > J1 > J2 > J3 > J4 > J5.
    Each joint node turns about its pivot's local Z, which build_scene.py
    placed on the encoder axis.

Not exported: the drag chains. They are modelled rigid; on a moving arm they
would cut through the links. (chains.py bends them for renders only.)
"""
import bpy, bmesh, sys, os, math, json, re
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
WORK = argv[0] if argv else os.path.join(os.path.dirname(bpy.data.filepath), "app_export")
RATIO = float(argv[1]) if len(argv) > 1 else 0.22
os.makedirs(WORK, exist_ok=True)

# Cable chain: rigid, see above. Studio / Trailer FX: render props of the
# trailer .blend (backdrop, encoder-ring effects), not part of the arm.
# Gripper: the trailer's gripper (body, servo, jaw, mount plate) is not shown
# in the app -- the arm ends at the J5 claws.
EXCLUDE_COLLECTIONS = {"Cable chain", "Studio (render only)", "Trailer FX",
                       "Gripper (trailer/cad)"}
LINKS = [("base", "ARM_ROOT"), ("j1", "PIVOT J1 Turret"), ("j2", "PIVOT J2 Upper arm"),
         ("j3", "PIVOT J3 Forearm"), ("j4", "PIVOT J4 Wrist"), ("j5", "PIVOT J5 Tool")]
PIVOT_TO_LINK = {p: l for l, p in LINKS}
MM = Matrix.Scale(1000.0, 4)

# ---- rest pose ----------------------------------------------------------------
# The rig's rest pose must be the CAD pose (every pivot at local Z = 0), because
# the app's viewZeroDeg values were measured against it. The trailer .blend
# keyframes the pivots, so drop all animation (in memory only; never saved)
# and put the joints back. Sub-pivots (gripper, claws) keep their current pose
# and are baked into J5.
for o in bpy.data.objects:
    if o.animation_data:
        o.animation_data_clear()
for _, p in LINKS[1:]:
    bpy.data.objects[p].rotation_euler.z = 0.0
bpy.context.view_layer.update()

# ---- joint calibration (the fan viewer's angle convention) -------------------
CAL = {}
try:
    sys.path.insert(0, r"D:\Claude\dragon-arm\tools")
    import poses
    poses.calibrate()
    for l, p in LINKS[1:]:
        o = bpy.data.objects[p]
        CAL[l] = {"viewer_zero": float(o["viewer_zero"]), "viewer_sign": float(o["viewer_sign"]),
                  "rest_z_deg": math.degrees(o.rotation_euler.z)}
except Exception as e:  # calibration is informative only
    print("CALIBRATION SKIPPED:", e)

def link_of(o):
    p = o.parent
    while p is not None:
        if p.name in PIVOT_TO_LINK:
            return PIVOT_TO_LINK[p.name]
        p = p.parent
    return "base"

def excluded(o):
    return any(c.name in EXCLUDE_COLLECTIONS for c in o.users_collection)

def slug(s):
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")

def run_in_edit(ob, fn):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    fn()
    bpy.ops.object.mode_set(mode="OBJECT")

def decimate(ob, tris):
    """Per part, so a 12-triangle PCB is left alone while a 40k-triangle gear
    is thinned. Parts under MIN_TRIS are never touched."""
    me = ob.data
    if getattr(me, "has_custom_normals", False):
        try:
            run_in_edit(ob, lambda: bpy.ops.mesh.customdata_custom_splitnormals_clear())
        except Exception as e:
            print("custom normals not cleared on", ob.name, e)
    # weld the STEP tessellation's split vertices, else collapse cannot reduce
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.002)
    bm.to_mesh(me); bm.free()
    ratio = max(RATIO, min(1.0, MIN_TRIS / max(tris, 1)))
    if ratio >= 0.999:
        return
    mod = ob.modifiers.new("dec", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=mod.name)

MIN_TRIS = 300

# ---- bake every mesh into its link frame -------------------------------------
dg = bpy.context.evaluated_depsgraph_get()
work_col = bpy.data.collections.new("APP_EXPORT")
bpy.context.scene.collection.children.link(work_col)

per_link = {l: [] for l, _ in LINKS}
src_tris = 0
for o in list(bpy.context.scene.objects):
    if o.type != "MESH" or excluded(o) or o.hide_render:
        continue
    link = link_of(o)
    pivot = bpy.data.objects[dict(LINKS)[link]]
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=False,
                                         depsgraph=dg)
    m = MM @ pivot.matrix_world.inverted() @ o.matrix_world
    me.transform(m)
    if m.determinant() < 0:
        me.flip_normals()
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    src_tris += tris
    ob = bpy.data.objects.new("tmp_" + o.name, me)
    work_col.objects.link(ob)
    per_link[link].append(ob)
    decimate(ob, tris)

exported = []
for link, objs in per_link.items():
    if not objs:
        continue
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    before = set(work_col.objects)
    run_in_edit(joined, lambda: bpy.ops.mesh.separate(type="MATERIAL"))
    parts = [joined] + [o for o in work_col.objects if o not in before]
    for part in parts:
        me = part.data
        if not me.polygons:
            bpy.data.objects.remove(part); continue
        # separate() leaves every slot on every piece; keep only the used one
        idx = me.polygons[0].material_index
        mname = me.materials[idx].name if idx < len(me.materials) and me.materials[idx] else "Default"
        for p in me.polygons:
            p.material_index = 0
        me.materials.clear()
        me.validate(clean_customdata=False)   # welding can leave degenerate faces
        me.shade_smooth()
        me.set_sharp_from_angle(angle=math.radians(35))
        name = f"{link}_{slug(mname)}"
        part.name = name; me.name = name
        exported.append((link, mname, part))

# ---- materials -----------------------------------------------------------------
def lin_to_srgb(c):
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055

materials = {}
for _, mname, _ in exported:
    if mname in materials:
        continue
    m = bpy.data.materials.get(mname)
    col, rough, metal = (0.5, 0.5, 0.5), 0.5, 0.0
    if m and m.node_tree:
        b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if b:
            col = tuple(b.inputs["Base Color"].default_value[:3])
            rough = float(b.inputs["Roughness"].default_value)
            metal = float(b.inputs["Metallic"].default_value)
    elif m:
        col = tuple(m.diffuse_color[:3])
    hexcol = "#" + "".join(f"{round(lin_to_srgb(v) * 255):02X}" for v in col)
    materials[mname] = {"id": "mat_" + slug(mname), "color": hexcol,
                        "roughness": round(rough, 3), "metalness": round(metal, 3)}

# ---- pivots (rest transforms relative to the parent pivot, mm) -----------------
pivots = []
prev = bpy.data.objects["ARM_ROOT"]
for link, pname in LINKS[1:]:
    o = bpy.data.objects[pname]
    rel = prev.matrix_world.inverted() @ o.matrix_world
    t = rel.to_translation() * 1000.0
    q = rel.to_quaternion()
    pivots.append({"link": link, "name": pname, "pos": [round(v, 3) for v in t],
                   "quat": [round(v, 6) for v in (q.w, q.x, q.y, q.z)]})
    prev = o

# bounds in the Blender frame (mm), CAD pose
lo = Vector((1e9,) * 3); hi = Vector((-1e9,) * 3)
for link, _, part in exported:
    piv = bpy.data.objects[dict(LINKS)[link]]
    m = piv.matrix_world @ Matrix.Scale(0.001, 4)
    for v in part.data.vertices:
        w = (m @ v.co) * 1000.0
        lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))

out_tris = sum(sum(len(p.vertices) - 2 for p in part.data.polygons) for _, _, part in exported)

# ---- export GLB (meshes only, already in link frames) ------------------------------
bpy.ops.object.select_all(action="DESELECT")
for _, _, part in exported:
    part.select_set(True)
glb = os.path.join(WORK, "dragon_arm_one.glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True,
                          export_yup=False, export_apply=True, export_materials="NONE",
                          export_texcoords=False, export_normals=True)

info = {"meshes": [{"link": l, "material": m, "name": p.name,
                    "tris": sum(len(f.vertices) - 2 for f in p.data.polygons)}
                   for l, m, p in exported],
        "materials": materials, "pivots": pivots, "calibration": CAL,
        "bounds_mm": {"min": list(lo), "max": list(hi)},
        "source": bpy.data.filepath, "ratio": RATIO,
        "source_tris": src_tris, "export_tris": out_tris}
with open(os.path.join(WORK, "rig.json"), "w") as f:
    json.dump(info, f, indent=1)
# ---- rig QML -----------------------------------------------------------------------
# Mesh files are named the way balsam names them: <mesh name>_mesh.mesh
def f(v, n=3):
    s = f"{v:.{n}f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s

def yup(v):  # Blender Z-up -> Qt Y-up, as the -90 deg X rotation on `frame` does
    return (v[0], v[2], -v[1])

bmin = yup(lo); bmax = yup(hi)
bmin, bmax = [min(a, b) for a, b in zip(bmin, bmax)], [max(a, b) for a, b in zip(bmin, bmax)]

Q = []
Q.append("// DragonArmOneRig.qml -- GENERATED by tools/export_3d_model.py. Do not edit;")
Q.append("// re-run tools/export_3d_model.ps1 when the CAD changes.")
Q.append("//")
Q.append(f"// Source: {os.path.basename(bpy.data.filepath)}, {src_tris} -> {out_tris} triangles.")
Q.append("// Units are millimetres. The hierarchy is Blender's (base > J1 > ... > J5), built")
Q.append("// in its Z-up frame and stood upright for Qt Quick 3D by `frame`.")
Q.append("//")
Q.append("// angles[i] turns joint i+1 about its own axis, in degrees, measured from the")
Q.append("// pose the CAD assembly was modelled in. Converting a robot's axis angles into")
Q.append("// these is the 3D view's job (RobotModels: viewZeroDeg / viewReversed).")
Q.append("")
Q.append("import QtQuick")
Q.append("import QtQuick3D")
Q.append("")
Q.append("Node {")
Q.append("    id: rig")
Q.append("")
Q.append("    property var angles: [0, 0, 0, 0, 0]")
Q.append("")
Q.append("    // The turning node of each joint, for tools that need to know where the")
Q.append("    // axes are (the 3D view's posing). Each turns about its own local Z.")
Q.append("    readonly property var joints: [" + ", ".join(p["link"] for p in pivots) + "]")
Q.append("")
Q.append("    // Which link a picked Model belongs to: \"base\", \"j1\" ... \"j5\". Every")
Q.append("    // Model is pickable, so View3D.pick() can tell the parts apart.")
Q.append("    function linkOf(node) {")
Q.append("        for (var n = node; n; n = n.parent) {")
Q.append("            if (n.objectName)")
Q.append("                return n.objectName")
Q.append("        }")
Q.append("        return \"\"")
Q.append("    }")
Q.append("")
Q.append("    // CAD-pose bounds in the scene frame (Y up), for framing the camera.")
Q.append(f"    readonly property vector3d boundsMin: Qt.vector3d({f(bmin[0],1)}, {f(bmin[1],1)}, {f(bmin[2],1)})")
Q.append(f"    readonly property vector3d boundsMax: Qt.vector3d({f(bmax[0],1)}, {f(bmax[1],1)}, {f(bmax[2],1)})")
Q.append("")
Q.append("    // Materials (colours are data from the .blend, not app styling)")
for mname, m in sorted(materials.items(), key=lambda kv: kv[1]["id"]):
    Q.append(f"    PrincipledMaterial {{ id: {m['id']}; baseColor: \"{m['color']}\"; "
             f"roughness: {f(m['roughness'])}; metalness: {f(m['metalness'])} }}   // {mname}")
Q.append("")

def models(link, indent):
    out = []
    for l, mname, part in sorted(exported, key=lambda e: e[2].name):
        if l != link:
            continue
        out.append(" " * indent + f"Model {{ source: \"meshes/{part.data.name}_mesh.mesh\"; "
                   f"pickable: true; materials: [ {materials[mname]['id']} ] }}")
    return out

Q.append("    Node {")
Q.append("        id: frame")
Q.append("        objectName: \"base\"")
Q.append("        eulerRotation.x: -90")
Q.append("")
Q.extend(models("base", 8))
indent = 8
for i, p in enumerate(pivots):
    pos, q = p["pos"], p["quat"]
    Q.append("")
    Q.append(" " * indent + f"Node {{   // {p['name']}")
    Q.append(" " * (indent + 4) + f"position: Qt.vector3d({f(pos[0])}, {f(pos[1])}, {f(pos[2])})")
    Q.append(" " * (indent + 4) + f"rotation: Qt.quaternion({f(q[0],6)}, {f(q[1],6)}, {f(q[2],6)}, {f(q[3],6)})")
    Q.append("")
    Q.append(" " * (indent + 4) + "Node {")
    Q.append(" " * (indent + 8) + f"id: {p['link']}")
    Q.append(" " * (indent + 8) + f"objectName: \"{p['link']}\"")
    # `|| 0`: during a robot switch `angles` can briefly be another robot's
    Q.append(" " * (indent + 8) + f"eulerRotation.z: rig.angles[{i}] || 0")
    Q.append("")
    Q.extend(models(p["link"], indent + 8))
    indent += 8
for i in range(len(pivots)):
    indent -= 8
    Q.append(" " * (indent + 4) + "}")
    Q.append(" " * indent + "}")
Q.append("    }")
Q.append("}")
with open(os.path.join(WORK, "DragonArmOneRig.qml"), "w", encoding="utf8", newline="\n") as fh:
    fh.write("\n".join(Q) + "\n")

print(f"EXPORTED {len(exported)} meshes, {src_tris} -> {out_tris} tris, glb {glb}")
for l, c in CAL.items():
    print("CAL", l, c)
