# Test Environment Documentation

## Current Target

- **Server**: `https://alpha.jitsi.net`
- **WebSocket URL**: `wss://alpha.jitsi.net/xmpp-websocket`
- **MUC Domain**: `conference.alpha.jitsi.net`
- **Focus JID**: `focus.alpha.jitsi.net`
- **Authentication**: SASL ANONYMOUS (no JWT required)
- **Lobby**: Not used (anonymous access)

## Verification History

| Date | Verified By | Status | Notes |
|------|-------------|--------|-------|
| 2024-01-01 | Phase 0 Spike | ✅ Working | Initial capture, both Jingle and Colibri2 observed |

## Known Characteristics

### Server Behavior
- Supports SASL ANONYMOUS authentication
- Uses both classic Jingle (XEP-0166) and Colibri2 for signaling
- Focus (Jicofo) joins MUC room and sends session-initiate
- SSRC tracking via Colibri2 source-add/source-remove messages

### Client Requirements
- Must support XMPP over WebSocket (RFC 7395)
- Must implement SASL ANONYMOUS
- Must handle stream restart after authentication
- Must parse Jitsi-specific presence extensions

### Limitations
- No JWT authentication support required for alpha.jitsi.net
- No lobby support required (anonymous access)
- No self-hosted support in Phases 0-4

## Testing Procedure

### Manual Testing
1. Launch the app
2. Join a room on alpha.jitsi.net
3. Verify connection to WebSocket
4. Verify SASL authentication succeeds
5. Verify MUC room join succeeds
6. Verify focus presence is received
7. Verify session-initiate (Jingle) is received
8. Verify Colibri2 conference info is received

### Automated Testing
- Unit tests use captured fixtures from `docs/fixtures/alphajitsi-join.json`
- Integration tests require live connection to alpha.jitsi.net
- Fixtures should be refreshed periodically

## Refresh Procedure

If behavior changes or tests start failing:

1. **Re-capture fixtures**:
   ```bash
   # Use Chrome DevTools to capture WebSocket traffic
   # Save as docs/fixtures/alphajitsi-join-{date}.json
   ```

2. **Update findings**:
   - Review `docs/findings.md`
   - Add new observations
   - Mark any changed behavior

3. **Update test environment doc**:
   - Update verification date
   - Note any changes in server behavior

## Future Considerations

### When to Add Self-Hosted Support
- After Phase 4 is complete
- Use docker-jitsi-meet for local testing
- Add JWT authentication support
- Add lobby handling

### When to Add Stable Target
- If alpha.jitsi.net becomes too unstable
- Consider using meet.jit.si (production)
- Or deploy local docker-jitsi-meet instance

## Contact Information

- Jitsi Community: https://community.jitsi.org
- Jitsi GitHub: https://github.com/jitsi
- alpha.jitsi.net status: Monitor Jitsi community announcements
