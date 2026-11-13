"""Package every skill under plugins/*/skills/ as dist/<skill>.skill
(a zip whose top level is the skill folder)."""
import glob
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
DIST = os.path.join(HERE, "dist")
os.makedirs(DIST, exist_ok=True)

for skill_md in glob.glob(os.path.join(HERE, "plugins", "*", "skills", "*", "SKILL.md")):
    skill_dir = os.path.dirname(skill_md)
    name = os.path.basename(skill_dir)
    base = os.path.join(DIST, name)
    archive = shutil.make_archive(base, "zip", os.path.dirname(skill_dir), name)
    target = base + ".skill"
    if os.path.exists(target):
        os.remove(target)
    os.replace(archive, target)
    print("wrote", target)
