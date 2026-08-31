# demo/ — the film runner

`film5-min-password-length.ipynb` talks to the **running Docker stack** (nothing is stubbed),
walks the film's scenes in order, asserts every step and screenshots the gallery into `shots/`.

What it proves, scene by scene: the default rung answers 5 → a deployment property claims the
restart rung (the notebook restarts the service itself) → an ADMIN sets 10 while the system runs
→ a length below the policy's own floor is refused and nothing changes → a row written straight
at the psql console is refused by the ladder, which falls through and says so in the report and
in the log → the browser shows the same refusal grouped per field.

## Run it

```bash
cd ~/Documents/git/portal && ./infra-up.sh        # the stack must be up first
cd ~/Documents/git/shared/demo
.venv/bin/jupyter lab film5-min-password-length.ipynb    # then: Run All
```

Headless, without opening JupyterLab:

```bash
.venv/bin/python -m nbclient film5-min-password-length.ipynb
```

## First-time setup

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/playwright install chromium      # skipped if the e2e suites already cached a browser
```

The notebook cleans up after itself: it deletes the `security_settings` row and removes the
compose override it wrote for the property scene. Test accounts carry the run's timestamp, so
repeated runs never collide. `.venv/` and `shots/` are gitignored — the screenshots are
regenerated on every run.
