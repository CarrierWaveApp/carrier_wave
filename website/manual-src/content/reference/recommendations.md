---
title: "Activation Recommendations"
description: "AI-powered park, gear, and band suggestions based on propagation and history"
weight: 9
showToc: true
---

Activation Recommendations is an experimental (alpha) feature that suggests optimal gear, parks, and bands for your next activation based on current propagation, your equipment history, award progress, and proximity.

{{< experimental "alpha" >}}

## Overview

Before starting a session, the recommendations screen analyzes multiple factors to suggest activations that maximize your chances of a successful outing.

## Scoring Dimensions

Recommendations are scored across seven weighted dimensions:

1. **Propagation fit** — Current band conditions and solar activity
2. **Proximity** — Distance to suggested parks
3. **Award progress** — Priority for parks that advance POTA awards
4. **Gear freshness** — Favors equipment you haven't used recently
5. **Park novelty** — Prefers parks you haven't activated
6. **Combo novelty** — Suggests new gear/park/band combinations
7. **Community interest** — Parks with recent spotter or hunter activity

## Serendipity Slider

Adjust the balance between practical and adventurous recommendations. Slide toward **practical** for safe, high-probability activations. Slide toward **adventurous** for novel combinations and less-visited parks.

## Milestone Gravity

When you're close to an award target (e.g., 998/1000 for POTA Kilo), recommendations strongly favor parks and bands that advance that goal.

## Equipment Pinning

Lock specific gear, a band, or a mode, and recommendations optimize around your constraints. For example, pin your QRP rig and get park/band suggestions that work best with low power.

## Widget

The Activation Suggestion widget (small and medium sizes) shows today's top recommended activation on your Home Screen.

## See Also

- [Equipment Catalog](/reference/equipment/) - Equipment inventory and specs
- [POTA Activations](/reference/pota/) - Park activation logging
- [Smart Spot Needs](/reference/smart-needs/) - Award progress tracking
