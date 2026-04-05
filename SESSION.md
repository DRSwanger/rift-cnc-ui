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

### Decisions / findings this session
_(updated as we work)_

### Where we stopped / next steps
_(updated when session ends or on checkpoint)_
