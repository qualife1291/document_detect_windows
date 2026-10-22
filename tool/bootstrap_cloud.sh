#!/usr/bin/env bash
# Linux-only coding/test toolchain; this does not provide Windows runtime support.
set -euo pipefail
export XDG_CONFIG_HOME=/workspace/.config PUB_CACHE=/workspace/.pub-cache
export ANALYZER_STATE_LOCATION_OVERRIDE=/workspace/.dartServer
export CI=true FLUTTER_SUPPRESS_ANALYTICS=true
python3 - <<'PY'
import hashlib,json,pathlib,tarfile,urllib.request
base=pathlib.Path('/workspace/toolchains');base.mkdir(exist_ok=True)
url='https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json'
data=json.load(urllib.request.urlopen(url,timeout=60))
for version in ['3.32.8','3.41.9','3.47.7']:
 target=base/version
 if (target/'flutter/bin/flutter').is_file(): continue
 record=next(r for r in data['releases'] if r['version']==version)
 archive=base/(version+'.tar.xz')
 urllib.request.urlretrieve(data['base_url']+'/'+record['archive'],archive)
 digest=hashlib.sha256()
 with archive.open('rb') as stream:
  for chunk in iter(lambda:stream.read(8*1024*1024),b''): digest.update(chunk)
 if digest.hexdigest()!=record['sha256']: raise RuntimeError('Flutter checksum mismatch')
 target.mkdir(exist_ok=True)
 with tarfile.open(archive) as bundle: bundle.extractall(target,filter='data')
 archive.unlink()
PY
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_cmd=/workspace/toolchains/3.32.8/flutter/bin/flutter
for project_dir in "$repo_dir" "$repo_dir/adapters/windows_doc_capture_uvc" "$repo_dir/example"; do
  cd "$project_dir"
  "$flutter_cmd" pub get
done
cd "$repo_dir/adapters/windows_doc_capture_desktop"
/workspace/toolchains/3.41.9/flutter/bin/flutter pub get
