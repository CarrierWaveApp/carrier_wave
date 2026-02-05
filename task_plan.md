# Task Plan: POTA Activation UX Improvements

## Goal
Enhance POTA activation experience with post-session upload prompt, activation map visualization with RST-based contact coloring, and map sharing capability.

## Current Phase
Phase 5 - Testing & Verification (awaiting user build)

## Phases

### Phase 1: Requirements & Discovery
- [x] Understand current logging session end flow
- [x] Understand current POTA activation row in logs
- [x] Understand current map implementation
- [x] Identify RST data availability in QSO model
- [x] Document findings in findings.md
- **Status:** complete

### Phase 2: Planning & Structure
- [x] Design post-session modal UI and flow
- [x] Design activation map view with RST coloring
- [x] Design share functionality approach
- [x] Document decisions with rationale
- **Status:** complete

### Phase 3: Implementation - Post-Session Modal
- [x] Create `POTAUploadPromptSheet.swift` in Views/Logger/
- [x] Add `@State var showUploadPrompt` to LoggerView
- [x] Modify `endSession()` call to check for unuploaded POTA QSOs first
- [x] Add UserDefaults key for "Don't Ask Again" preference
- [x] Show success state in modal after upload completes
- **Status:** complete

### Phase 4: Implementation - Activation Map
- [x] Create `ActivationMapView.swift` in Views/POTAActivations/
- [x] Add RST color computation helper (average sent+received → color)
- [x] Create RST-colored markers for the map
- [x] Add map icon button to `ActivationRow`
- [x] Wire up NavigationLink or sheet to `ActivationMapView`
- [x] Add share button using existing `ActivationShareRenderer`
- **Status:** complete

### Phase 5: Testing & Verification
- [ ] Verify modal appears after ending session
- [ ] Verify map displays correctly with RST colors
- [ ] Verify share functionality works
- [ ] Document test results in progress.md
- **Status:** pending

### Phase 6: Delivery
- [ ] Review all changes
- [ ] Ensure deliverables are complete
- [ ] Deliver to user
- **Status:** pending

## Key Questions
1. ~~What triggers "ending a logging session"?~~ → `endSession()` in LoggingSessionManager
2. ~~Should modal only appear for POTA activations with unuploaded QSOs?~~ → Yes, only unuploaded
3. ~~What RST values map to what colors?~~ → Green: 599/59, Yellow: 579/559/57/55, Red: <55 (average of sent+received)
4. ~~What format should the shared map be?~~ → Same image share as existing, via ActivationShareRenderer
5. ~~Should the map show all contacts or just the current activation?~~ → Just activation (simple full-screen view)

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Modal only for POTA + unuploaded | Don't pester when nothing to upload |
| Upload Now / Later / Don't Ask Again | User control |
| Average rstSent + rstReceived | Both contribute to quality |
| Green ≥55 avg, Yellow ≥45 avg, Red <45 | Maps RST to 3-tier color |
| Reuse ActivationShareRenderer | Consistent output, less code |
| Simple full-screen map | No filtering complexity for single activation |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
|       | 1       |            |

## Notes
- Update phase status as you progress: pending → in_progress → complete
- Re-read this plan before major decisions (attention manipulation)
- Log ALL errors - they help avoid repetition
