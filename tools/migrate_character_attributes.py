import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHARACTER_DIR = ROOT / "data" / "characters"


def default_attributes():
    return {
        "sets": {
            "base": {
                "strength": 5,
                "agility": 5,
                "constitution": 5,
            },
            "combat": {
                "max_hp": 50,
                "attack_power": 5,
                "defense": 2,
                "speed": 5,
                "accuracy": 70,
                "crit_chance": 0.05,
                "crit_damage": 1.5,
                "evasion": 0.05,
            },
        },
        "resources": {
            "hp": {
                "current": 50,
            }
        },
    }


def migrate_record(record: dict) -> dict:
    migrated = json.loads(json.dumps(record))
    if "attributes" not in migrated:
        attrs = default_attributes()
        combat = migrated.get("combat", {})
        stats = combat.get("stats", {})
        attrs["sets"]["combat"]["max_hp"] = int(stats.get("max_hp", stats.get("hp", attrs["sets"]["combat"]["max_hp"])))
        attrs["sets"]["combat"]["attack_power"] = int(stats.get("damage", attrs["sets"]["combat"]["attack_power"]))
        attrs["sets"]["combat"]["defense"] = int(stats.get("defense", attrs["sets"]["combat"]["defense"]))
        attrs["sets"]["combat"]["speed"] = float(stats.get("speed", attrs["sets"]["combat"]["speed"]))
        attrs["sets"]["combat"]["accuracy"] = float(stats.get("accuracy", attrs["sets"]["combat"]["accuracy"]))
        attrs["sets"]["combat"]["crit_chance"] = float(stats.get("crit_chance", attrs["sets"]["combat"]["crit_chance"]))
        attrs["sets"]["combat"]["crit_damage"] = float(stats.get("crit_damage", attrs["sets"]["combat"]["crit_damage"]))
        attrs["sets"]["combat"]["evasion"] = float(stats.get("evasion", attrs["sets"]["combat"]["evasion"]))
        attrs["resources"]["hp"]["current"] = int(stats.get("hp", attrs["sets"]["combat"]["max_hp"]))
        migrated["attributes"] = attrs

    combat = migrated.get("combat", {})
    if isinstance(combat, dict) and "stats" in combat:
        combat = dict(combat)
        combat.pop("stats", None)
        migrated["combat"] = combat

    return migrated


def main() -> None:
    for path in sorted(CHARACTER_DIR.glob("*.json")):
        with path.open("r", encoding="utf-8") as fh:
            record = json.load(fh)
        migrated = migrate_record(record)
        if migrated != record:
            with path.open("w", encoding="utf-8") as fh:
                json.dump(migrated, fh, ensure_ascii=False, indent=2)
                fh.write("\n")
            print(f"migrated {path.name}")
        else:
            print(f"unchanged {path.name}")


if __name__ == "__main__":
    main()
