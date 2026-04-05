# CNC UI Session Notes

**Project:** AlienWoodshop Custom Onefinity UI  
**UI:** http://192.168.1.121:8888  
**Source:** /home/dallas/.claude/cnc_ui/index.html  
**Controller:** http://cnc.onefinity.com (bbctrl/BuildBotics)  
**WebSocket:** ws://cnc.onefinity.com/websocket  

---

## 2026-04-05 — Live Test Day

### Status at session start
- Full UI built and serving
- First live test against real controller today
- VM crashed mid-session; recovering from memory

### What needs verifying today
- [ ] ABS position field names (`x/y/z` for machine coords)
- [ ] Load relay API: `PUT /api/config` with `load-0-enabled`
- [ ] Jog directions (may be reversed)
- [ ] Unpause endpoint: `/api/unpause`
- [ ] Resume workflow: pause→unpause first, then stop→resume

### Findings confirmed on live machine
- E-stop endpoints: `PUT /api/estop` (trigger), `PUT /api/clear` (release)
- Relay WS fields: `1oa` / `2oa` — not `mist`/`flood` as assumed
- Individual axis home: `G28.2 X0` via WS (not REST)
- Resume feature disabled (`ENABLE_RESUME = false`) pending further testing

### Next session backlog
1. File manager overhaul — Windows Explorer style, fix delete
2. Macro editor — edit name, GCode, button color
3. MDI section — manual GCode input below GCode viewer
4. Probe Z button — with workpiece thickness prompt for auto-offset
