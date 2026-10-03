Pocket Vault is a cross-platform (iOS + Android, via SwiftUI/Skip transpilation) savings-goal app. Core idea: pick something you're saving for, set a target amount, and watch visual progress toward it — gamified enough to keep you coming back, but a real finance tool underneath.

Core features:

Goals — set a savings goal (preset categories like travel/tech/car, or a custom one), target amount, and target date; track progress toward it, with an optional custom "voxel" 3D build that fills in as you save (BuildStudioView, GoalKind)
Budget tracking — a budget tracker tab, with bank sync support (Plaid) and a savings trend chart
Shared/social — shared budgets with a partner, a friends/leaderboard system (streaks, friend codes) to compare progress with others
Streaks — daily-habit streak tracking (StreakManager) tied into the leaderboard
AI chat — an in-app AI assistant (AichatView, AIGoalBuilderService) that can suggest/build goals
Pro subscription — paywalled features via RevenueCat (EntitlementManager, PaywallView)

Accounts: supports full sign-up/sign-in (email, Apple/social) as well as a local-only guest mode — guest data lives only on-device until they create a free account, at which point it migrates over. The app nudges guests to sign up when they're about to lose something (e.g. GuestSavePromptView) or hit a feature that needs a verified identity (friends/leaderboard, shared budgets — AccountRequiredGateView).

Onboarding: a short, Duolingo-style first-run flow (welcome screen → goal/amount form) with its own mascot and lightweight celebratory animations, plus a guided feature tour of the main tabs the first time someone lands in the app.

Platform note: the codebase leans hard on keeping behavior identical between native SwiftUI (iOS) and Skip's Kotlin transpilation (Android) — a lot of the code comments are specifically about avoiding SwiftUI patterns that don't render correctly once transpiled.
