// Ensures the Homarr group named by HOMARR_ADMIN_GROUP exists with the `admin`
// permission. OIDC users are placed in Homarr groups by name from the groups
// claim, and Homarr offers no env var or REST endpoint to create one.
// Prints "changed" or "unchanged"; exits 3 while Homarr's schema is not ready.
const Database = require("/app/node_modules/better-sqlite3");
const { randomUUID } = require("node:crypto");

const name = process.env.HOMARR_ADMIN_GROUP;
if (!name) throw new Error("HOMARR_ADMIN_GROUP is not set");

const db = new Database("/appdata/db/db.sqlite");
db.pragma("busy_timeout = 5000");

if (!db.prepare("select 1 from sqlite_master where name = 'group'").get()) {
  console.log("not-ready");
  process.exit(3);
}

const seed = db.transaction(() => {
  let changed = false;
  let group = db.prepare('select id from "group" where name = ?').get(name);
  if (!group) {
    const { position } = db.prepare('select coalesce(max(position), 0) + 1 as position from "group"').get();
    group = { id: randomUUID() };
    db.prepare('insert into "group" (id, name, position) values (?, ?, ?)').run(group.id, name, position);
    changed = true;
  }
  const hasAdmin = db.prepare("select 1 from groupPermission where group_id = ? and permission = 'admin'").get(group.id);
  if (!hasAdmin) {
    db.prepare("insert into groupPermission (group_id, permission) values (?, 'admin')").run(group.id);
    changed = true;
  }
  return changed;
});

console.log(seed() ? "changed" : "unchanged");
