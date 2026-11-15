# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Static HTML/CSS: one self-contained `index.html` with inline CSS and JS, no build step, no external images. Deploys to GitHub Pages or Vercel. Google Fonts is the only external dependency.

## Users

- **People walking home alone at night** who want someone to know if something goes wrong, without having to reach for a panic button.
- **Their friends (the "circle")**, who get alerted and act on it.
- Visitors to this site (inferred, not confirmed): SunHacks 2026 judges, other hackers, and anyone who opens the GitHub link. They need to understand the mechanism within seconds.

## Product Purpose

Pupdate is an iPhone app (a SunHacks 2026 hackathon project, ASU) with a cartoon dog that walks you home at night. Every so often the dog asks "Still good?" and you answer by petting it, either by rubbing across the dog on screen or by tapping "Pet" on the Lock Screen. If you go quiet, the dog gets worried, then scared, then alerts your friends with your live location, your route and a short summary.

This repository is the one-page marketing site for the app.

## Positioning

Silence becomes the signal. Location apps show where you are; Pupdate tells your friends when something's wrong, even if you can't. The check-in is an act of care (petting a dog), not a form or a panic button, and it is built to resist coercion.

- Tagline: "Pet me if you're OK."
- One-liner: "Location apps show where you are. Pupdate tells your friends when something's wrong, even if you can't."

## Operating Context

A walk at night, phone in hand or pocket, often on a college campus. Check-ins happen on screen or from the Lock Screen and Dynamic Island through a Live Activity. The friends' side is a full-screen alert with a map, a summary and an "I've got them" button.

## Capabilities and Constraints

- **Pet to check in.** The dog asks, you pet it, it wags. Check-ins earn XP.
- **Escalation ladder:** calm → asking → worried → last chance → countdown → friends alerted.
- **Coercion-proof.** A duress PIN shows a normal "all clear" on your screen but quietly alerts friends. Holding the dog for 2 seconds sends a silent alert. A late pet can't cancel an alert; only a friend can close it.
- **Pace watch (Google Gemini).** Notices running, backtracking, sudden stops or getting into a car, and checks in early with a reason. AI never decides whether an alert fires; fixed rules do.
- **Safer routes.** Picks walking routes around spots friends flagged as "avoid" or "caution".
- **Live Activity.** Shows the dog's mood, a countdown, turn-by-turn directions and a Pet button that works without unlocking.
- **Circle.** Friends see your walk only while you're walking.
- **Growth.** Puppy → Scout Pup (bandana) → Guardian Dog (vest + headlamp), plus a safe-walk streak.
- **Stack:** SwiftUI, ActivityKit Live Activities, App Intents, MapKit, FastAPI, Python, Google Gemini, MongoDB Atlas, Vultr.
- **Known limits:** not an emergency service (call 911). Friends need the app open to get alerts (no push yet). It's a hackathon prototype. Demo routes and safe spots are sample data.
- **Not published:** there's no App Store listing, so the site shows no App Store badge.
- **Repository:** https://github.com/JeremyEltho/walkbuddy
- **Demo video:** not yet available. Its link is a `#demo` placeholder.

## Brand Commitments

- Name "Pupdate". The dog is an original cartoon puppy and must not resemble any existing character.
- Voice: short, warm and a little funny ("Good dog. You made it home."), never alarmist and never childish.
- Visual pins from the user's brief (binding, recorded here only because they were explicitly given): a night-time, premium look, not childish; deep navy ground with a star field; gold accent; mood colors sky for asking, amber for worried, red for alerts and mint for safe; Bricolage Grotesque and Figtree.

## Evidence on Hand

- The product description, features and stack above, all from the team.
- Origin: built at SunHacks 2026 (ASU).
- Not available, and must never be invented: testimonials, user counts, download numbers, press logos, App Store availability, or any claim that it works as an emergency service.

## Product Principles

1. **Silence is the signal.** Nothing should depend on the user finding a button in a bad moment.
2. **Rules decide, AI advises.** Gemini can prompt an early check-in but never fires or cancels an alert.
3. **Share only while it matters.** Location is shared during a walk or an alert, never otherwise.
4. **Honest about limits.** It's a prototype, not an emergency service, and the site says so plainly.
5. **Care, not fear.** The dog makes checking in feel like affection, not surveillance.

## Accessibility & Inclusion

The site meets WCAG AA contrast, uses real alt text and aria labels, shows a visible keyboard focus ring, and respects `prefers-reduced-motion`. Every interactive demo works with mouse, touch and keyboard.
