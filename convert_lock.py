import yaml
import json

with open('pubspec.lock', 'r') as f:
    data = yaml.safe_load(f)

with open('pubspec.lock.json', 'w') as f:
    json.dump(data, f, indent=2)
