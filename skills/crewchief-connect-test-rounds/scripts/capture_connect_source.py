"""One-time capture (11/11 redesign): copies the step data of the hand-kept Connect pack into source/, where
gen_connect.py reads it. Run it only against a pack that still has the per-size layout (connect-1k-...); after the
regeneration the files in source/ are the source and are edited there.

  source/workloads/<new name>.workload.json   a size-free workload exactly as it was (the generator changes names, shared
                                               blocks and run values when it writes the pack)
  source/manifest.json                         new name -> old name and folder
  source/specs.json                            the 9 TestAuto workflow specs (provider x direction), taken at 1K, 4 threads
  source/profiles.json                         the 9 run profile rows, taken at 1K, 4 threads
  source/schedules.json                        day and time of today's schedules

Usage: python capture_connect_source.py <packRoot>   (e.g. C:\\devops\\repos\\speed-merchants\\CrewChief\\packs\\connect)
"""
import glob
import json
import os
import re
import shutil
import sys

root = os.path.abspath(sys.argv[1])
here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(here, 'source')
wl = os.path.join(root, 'workloads', 'connect')
SPEC = re.compile(r"\$specJson = @'\n(.*?)\n'@", re.S)
PROFILES = re.compile(r"\$profiles = @'\n(.*?)\n'@", re.S)

# Old name -> new name, for the per-size files that are carried once.
RENAMED = {
    'connect-1k-bootstrap-main-only': 'connect-bootstrap-main',
    'connect-1k-exports-prepare-all': 'connect-exports-prepare-all',
    'connect-1k-imports-prepare-all': 'connect-imports-prepare-all',
    'connect-1k-databricks-credentials-refresh': 'connect-databricks-credentials-refresh',
    'connect-1k-snowflake-credentials-refresh': 'connect-snowflake-credentials-refresh',
    'connect-1k-synapse-credentials-refresh': 'connect-synapse-credentials-refresh',
}
# Not carried: replaced by the common pack, built by the generator, or per-size leftovers nothing calls.
DROPPED = {'connect-api-key-set-all', 'connect-api-key-set-main', 'connect-api-key-set-profisee-to-profisee',
           'connect-database-baseline-create', 'connect-preflight', 'connect-setup'}
SIZED = re.compile(r'^(schedule-connect|connect-test|connect)-(1k|1m)-')

files = {}
for path in glob.glob(os.path.join(wl, '**', '*.workload.json'), recursive=True):
    files[os.path.basename(path)[:-len('.workload.json')]] = path
if not any(SIZED.match(n) for n in files):
    sys.exit('this pack no longer has the per-size layout; source/ is the source now')

if os.path.isdir(out):
    shutil.rmtree(out)
os.makedirs(os.path.join(out, 'workloads'))
manifest = {}
for old, path in sorted(files.items()):
    if old in DROPPED:
        continue
    if SIZED.match(old) and old not in RENAMED:
        continue
    new = RENAMED.get(old, old)
    folder = os.path.relpath(os.path.dirname(path), wl).replace(os.sep, '/')
    folder = re.sub(r'/(1k|1m)(/t\d+)?$', '', folder)
    if folder in ('internal/1k', 'internal/1k/t4'):
        folder = 'internal/shared'
    shutil.copyfile(path, os.path.join(out, 'workloads', new + '.workload.json'))
    manifest[new] = {'from': old, 'folder': folder}


def load(name):
    with open(files[name], encoding='utf-8-sig') as f:
        return json.load(f)


names = json.load(open(os.path.join(root, 'reference-kv', 'connect', 'workflows.json'), encoding='utf-8-sig'))['entries']
specs = {}
for s in load('connect-1k-testauto-workflows-create')['steps']:
    m = SPEC.search(s['inline'].get('scriptContent', '').replace('\r\n', '\n'))
    if m:
        spec = json.loads(m.group(1))
        k = re.match(r'^connect-1k-(.+)-4t$', spec['Key'])
        if k:
            spec['DisplayName'] = names[spec['Key']]
            specs[k.group(1)] = spec
assert len(specs) == 9, sorted(specs)
script = load('connect-1k-testauto-run-profiles-create')['steps'][1]['inline']['scriptContent'].replace('\r\n', '\n')
profiles = [p for p in json.loads(PROFILES.search(script).group(1)) if p['WorkerThreadCount'] == 4]
assert len(profiles) == 9, len(profiles)
schedules = {}
for name in sorted(files):
    m = re.match(r'^schedule-connect-(1k|1m)-(.+)$', name)
    if m:
        g = load(name)['globalParameters']
        schedules['%s-%s' % (m.group(1), m.group(2))] = {'Days': g['DaysOfWeek'], 'Time': g['StartTime'], 'OldTarget': g['TargetWorkload']}


def dump(name, obj):
    with open(os.path.join(out, name), 'w', encoding='utf-8', newline='\n') as f:
        json.dump(obj, f, indent=1, ensure_ascii=False)


dump('manifest.json', manifest)
dump('specs.json', specs)
dump('profiles.json', profiles)
dump('schedules.json', schedules)
print('captured %d workloads, %d specs, %d profile rows, %d schedules into %s' % (len(manifest), len(specs), len(profiles), len(schedules), out))
