// Syntax-checks every Lua file, then runs the Lua tests with fengari (Lua 5.3; FiveM runs 5.4, so the core avoids
// <const>/<close> and the CfxLua ?. operator):
//   tests/callback.test.lua   the callback system in import.lua
//   tests/framework.test.lua  the server / client framework layer against mocked ESX, QBCore, Qbox and standalone
// node tests/run.cjs [path to a folder with node_modules/fengari]
const path = require('path'), fs = require('fs');
const base = process.argv[2] || path.join(__dirname, '../../../../../.lucille/state/lua-check');
const { lua, lauxlib, lualib, to_luastring } = require(path.join(base, 'node_modules/fengari'));
const root = path.join(__dirname, '..');

const walk = d => fs.readdirSync(path.join(root, d), { withFileTypes: true })
  .flatMap(e => e.isDirectory() ? walk(`${d}/${e.name}`) : e.name.endsWith('.lua') ? [`${d}/${e.name}`] : []);
const files = ['fxmanifest.lua', 'config.lua', 'import.lua', ...['shared', 'server', 'client'].flatMap(walk)];
const source = f => fs.readFileSync(path.join(root, f), 'utf8');

let failed = 0;
for (const f of files) {
  const L = lauxlib.luaL_newstate();
  if (lauxlib.luaL_loadbuffer(L, to_luastring(source(f)), null, to_luastring('@' + f)) !== lua.LUA_OK) {
    failed++; console.log('FAIL', lua.lua_tojsstring(L, -1));
  } else console.log('ok  ', f);
}

function run(test, pushArg) {
  console.log(`\n${test}`);
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  if (lauxlib.luaL_loadbuffer(L, to_luastring(source(test)), null, to_luastring('@' + test)) !== lua.LUA_OK) {
    console.log('FAIL', lua.lua_tojsstring(L, -1)); return 1;
  }
  pushArg(L);
  if (lua.lua_pcall(L, 1, 1, 0) !== lua.LUA_OK) { console.log('FAIL', lua.lua_tojsstring(L, -1)); return 1; }
  return lua.lua_tointeger(L, -1);
}

failed += run('tests/callback.test.lua', L => lua.lua_pushstring(L, to_luastring(source('import.lua'))));
failed += run('tests/framework.test.lua', L => {
  lua.lua_newtable(L);
  for (const f of files) {
    lua.lua_pushstring(L, to_luastring(source(f)));
    lua.lua_setfield(L, -2, to_luastring(f));
  }
});

console.log(failed ? `\n${failed} failure(s)` : '\nall passed');
process.exit(failed ? 1 : 0);
