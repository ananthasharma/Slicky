import SwiftUI

@MainActor
final class PetModel: ObservableObject {
    /// Hop timeline. `nil` while standing still.
    /// -1...0 = crouch, 0...1 = airborne, 1...2 = landing recoil.
    @Published var phase: Double?
    @Published var held = false
    /// Decays from 1 to 0 after a click; drives the happy face.
    @Published var excitement: Double = 0
    @Published var waving: Double = 0
    /// Where to point the eyes, each axis -1...1.
    @Published var look: CGPoint = .zero
    @Published var paused = false
    /// An app is being dragged over the robot — arms up, ready to catch it.
    @Published var beckoning = false
    /// A newer build is waiting; the face switches to  >_  until it's installed.
    @Published var updateAvailable = false

    @Published var pressed = false
    @Published var anticipating = false
    @Published var badge: NSImage?
    @Published var badgeLife: Double = 0
    /// Expanding rings, one per click; each counts down from 1.
    @Published var pulses: [Double] = []
    @Published var presenting = false
    @Published var eating: Double = 0
    /// Which side the page flies in from: +1 right, -1 left.
    @Published var eatSide: Double = 1

    var airborne: Bool {
        guard let phase else { return false }
        return phase > 0 && phase < 1
    }

    var snapshot: PetSnapshot {
        PetSnapshot(phase: phase, held: held, excitement: excitement, waving: waving,
                    beckoning: beckoning, notify: updateAvailable,
                    pressed: pressed, anticipating: anticipating,
                    presenting: presenting, eating: eating, eatSide: eatSide)
    }

    func celebrate(_ icon: NSImage?, rings: Int) {
        badge = icon
        badgeLife = icon == nil ? 0 : 1
        excitement = 1
        pulses.append(1)
        for extra in 1..<max(1, rings) {
            let delay = Double(extra) * 0.16
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.pulses.append(1)
            }
        }
    }
}

struct PetSnapshot {
    var phase: Double?
    var held = false
    var excitement = 0.0
    var waving = 0.0
    var beckoning = false
    var notify = false
    var pressed = false
    var anticipating = false
    var presenting = false
    var eating = 0.0
    var eatSide = 1.0
}

struct Pose {
    var squashX: Double = 1
    var squashY: Double = 1
    var bob: Double = 0
    var legTuck: Double = 0
    /// Degrees of arm lift: 0 hangs down, 180 points straight up.
    var armAngle: Double = 0
    var waveAngle: Double?
    var openMouth = false
    var antennaBend: Double = 0
    var eyeOpen: Double = 1
    var smile: Double = 0
    var thrust: Double = 0
    var shadow: Double = 1
    /// Draw the  >_  face instead of the usual eyes.
    var notify = false
    var glowBoost: Double = 0

    static func make(time t: Double, _ state: PetSnapshot) -> Pose {
        let phase = state.phase
        let held = state.held
        let excitement = state.excitement
        let waving = state.waving

        var pose = Pose()
        pose.notify = state.notify
        let breathe = sin(t * 1.7)

        pose.bob = breathe * 2.5
        pose.armAngle = 10 + breathe * 4
        pose.antennaBend = sin(t * 2.1) * 3
        pose.smile = excitement

        // Blinks: a slow rhythm plus an offset one so they never look metronomic.
        let blink = max(blinkPulse(t, every: 3.9, at: 0.0), blinkPulse(t, every: 7.3, at: 2.1))
        pose.eyeOpen = 1 - blink

        if waving > 0.01 {
            pose.waveAngle = 150 + sin(t * 12) * 22
        }

        if let phase {
            if phase < 0 {                                  // crouch, anticipation
                let u = min(1, max(0, phase + 1))
                pose.squashY = 1 - 0.20 * u
                pose.squashX = 1 + 0.16 * u
                pose.bob = 0
                pose.armAngle = 10 - 34 * u
                pose.antennaBend = 10 * u
                pose.shadow = 1 + 0.1 * u
            } else if phase <= 1 {                          // airborne
                let vertical = cos(.pi * phase)             // +1 rising, -1 falling
                let stretch = abs(vertical)
                pose.squashY = 1 + 0.22 * stretch
                pose.squashX = 1 - 0.16 * stretch
                pose.bob = 0
                pose.legTuck = sin(.pi * phase)
                pose.armAngle = 145 + sin(.pi * phase) * 22
                pose.openMouth = true
                pose.antennaBend = -14 * vertical
                pose.thrust = max(0, vertical) * 1.0
                pose.shadow = 1 - sin(.pi * phase) * 0.55
                pose.eyeOpen = max(pose.eyeOpen, 0.9)
            } else {                                        // landing recoil
                let u = min(1, phase - 1)
                let recoil = sin(.pi * u)
                pose.squashY = 1 - 0.24 * recoil
                pose.squashX = 1 + 0.20 * recoil
                pose.bob = 0
                pose.armAngle = 10 + 46 * recoil
                pose.antennaBend = 16 * recoil
            }
        }

        if state.anticipating {
            // Coiled, wide-eyed, antenna buzzing: something is about to happen.
            pose.squashY = 0.96
            pose.squashX = 1.04
            pose.bob = -1
            pose.armAngle = 26 + sin(t * 9) * 6
            pose.antennaBend = sin(t * 14) * 6
            pose.eyeOpen = 1
            pose.glowBoost = 0.6 + 0.4 * sin(t * 9)
        }

        if state.pressed {
            pose.squashY = 0.90
            pose.squashX = 1.08
            pose.bob = 0
            pose.armAngle = 20
            pose.eyeOpen = min(pose.eyeOpen, 0.55)
        }

        if state.presenting {
            pose.armAngle = 52 + sin(t * 3) * 5
            pose.bob = sin(t * 2.2) * 1.6
            pose.eyeOpen = max(pose.eyeOpen, 0.85)
        }

        if state.eating > 0 {
            let chew = 1 - state.eating          // 0 → 1
            pose.armAngle = 74 - chew * 20
            pose.openMouth = chew > 0.45 && chew < 0.86
            if chew > 0.86 {
                // Two quick chomps once it's in.
                let bite = sin((chew - 0.86) / 0.14 * .pi * 2)
                pose.squashY = 1 - 0.05 * abs(bite)
                pose.squashX = 1 + 0.04 * abs(bite)
            }
            pose.eyeOpen = chew > 0.86 ? 0.35 : 1
        }

        if state.beckoning {
            let eager = sin(t * 7)
            pose.bob = eager * 4 - 2
            pose.squashY = 1 + eager * 0.03
            pose.squashX = 1 - eager * 0.03
            pose.armAngle = 128 + eager * 14
            pose.antennaBend = sin(t * 9) * 7
            pose.eyeOpen = 1
            pose.openMouth = true
            pose.waveAngle = nil
        }

        if held {
            pose.squashY = 1.06
            pose.squashX = 0.96
            pose.bob = 0
            pose.legTuck = 0.35 + sin(t * 9) * 0.15
            pose.armAngle = 152 + sin(t * 13) * 24
            pose.openMouth = true
            pose.antennaBend = sin(t * 11) * 12
            pose.shadow = 0.35
        }

        if excitement > 0.01 {
            let wiggle = sin(t * 16) * excitement
            pose.armAngle += wiggle * 18
            pose.antennaBend += wiggle * 6
            pose.squashY += excitement * 0.05
        }

        return pose
    }

    private static func blinkPulse(_ t: Double, every period: Double, at offset: Double) -> Double {
        let p = (t - offset).truncatingRemainder(dividingBy: period)
        guard p >= 0, p < 0.14 else { return 0 }
        return sin(.pi * p / 0.14)
    }
}
