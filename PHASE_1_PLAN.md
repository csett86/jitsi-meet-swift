# Phase 1 - XMPP/MUC/Jingle Signaling Layer: Implementation Plan

## Overview

Phase 1 builds on Phase 0 to create a production-ready signaling library. Most of the core implementation was created in Phase 0, so Phase 1 focuses on:

1. **Refinement**: Improve error handling, add missing features
2. **Testing**: Ensure all components work with live alpha.jitsi.net
3. **Integration**: Wire up all components into a cohesive API

## Current State (from Phase 0)

✅ **Already Implemented**:
- XMPPWebSocketConnection with streaming XML parsing
- SASLAuthenticator for ANONYMOUS auth
- Stanza parsing (Presence, IQ, Message)
- Jingle session parsing (XEP-0166)
- Colibri2 content parsing
- MUC session management
- Service discovery (XEP-0030)
- TURN discovery (XEP-0215)
- JitsiConference orchestration
- Comprehensive unit tests

## Phase 1 Tasks

### 1. Refine XMPPWebSocketConnection
- [ ] Add reconnection with exponential backoff
- [ ] Handle connection state transitions properly
- [ ] Add ping/pong for connection health
- [ ] Handle stream errors gracefully

### 2. Complete SASL Authentication
- [ ] Handle all SASL states properly
- [ ] Add support for PLAIN and SCRAM-SHA-1 (for future JWT auth)
- [ ] Handle auth failure with proper error messages

### 3. Improve Stanza Parsing
- [ ] Use proper XMLParser instead of regex where possible
- [ ] Handle partial/fragmented stanzas
- [ ] Add better error recovery
- [ ] Parse all Jitsi-specific presence extensions

### 4. Complete Jingle Support
- [ ] Handle session-accept, session-terminate
- [ ] Handle content-add, content-remove, content-modify
- [ ] Handle transport-info (trickle ICE)
- [ ] Handle session-info

### 5. Complete Colibri2 Support
- [ ] Handle conference updates
- [ ] Handle channel updates
- [ ] Handle source-add/source-remove properly
- [ ] Map Colibri2 to WebRTC concepts

### 6. Complete MUC Session
- [ ] Handle MUC room configuration
- [ ] Handle participant roles and affiliations
- [ ] Handle MUC errors
- [ ] Handle room destruction

### 7. Complete Service Discovery
- [ ] Query disco#items for available services
- [ ] Cache disco results
- [ ] Handle disco errors

### 8. Complete TURN Discovery
- [ ] Query external services (XEP-0215)
- [ ] Parse TURN server information
- [ ] Handle TURN authentication

### 9. Complete JitsiConference
- [ ] Handle full connection flow
- [ ] Handle reconnection
- [ ] Handle focus failover
- [ ] Expose proper public API

### 10. Add Integration Tests
- [ ] Test with live alpha.jitsi.net
- [ ] Test connection flow end-to-end
- [ ] Test MUC join/leave
- [ ] Test session description reception

## Definition of Done

- [ ] `JitsiConference.connect()` successfully joins a room and fires "session description received" event on alpha.jitsi.net
- [ ] Unit tests pass against Phase 0 fixture transcript
- [ ] `BackendCapabilities` is populated correctly via live disco queries
- [ ] No media/WebRTC code has been written yet — this phase is signaling only

## Implementation Order

1. **Fix any issues in current implementation** (based on fixture testing)
2. **Add missing features** (reconnection, error handling, etc.)
3. **Create integration tests** with live server
4. **Verify all unit tests pass**
5. **Document the public API**

## Estimated Duration

- Refinement: 2-3 days
- Testing: 2-3 days
- Documentation: 1 day

## Dependencies

- Phase 0 must be complete (✅ DONE)
- alpha.jitsi.net must be accessible

## Success Criteria

1. All unit tests pass
2. Integration test connects to alpha.jitsi.net successfully
3. Session description is received from focus
4. All stanza types are parsed correctly
5. Error handling is robust
