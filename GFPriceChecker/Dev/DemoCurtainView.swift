//
//  DemoCurtainView.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-10-31.
//

#if DEBUG
import SwiftUI

/// What a scripted take shows in place of `LaunchScreenView`: nothing at all.
///
/// The launch screen is white under a faint blue-green gradient, with a logo
/// and a tagline. That is light, but it is not flat, and the host finds where a
/// take begins by looking for the frames with nothing drawn on them —
/// TrendFit's `launch_frame.py` measures a spread of about 5 across a 4×4 grid
/// for an empty frame against 18 or more once the app draws, and cuts after the
/// last flat hold. Against the logo, it would cut on the system launch screen
/// and open the take a curtain early.
///
/// `systemBackground` because that is what the system launch screen is
/// (`UILaunchScreen_Generation`, with nothing configured). The two then read
/// as one motionless frame, which is the still gap the detector cuts on, so
/// `launch_frame.py` ports with its constants unchanged.
///
/// Held by `DemoDirector.start`, not by a timer, so it covers the seed however
/// long that takes and lifts `curtainSeconds` after.
struct DemoCurtainView: View {
    var body: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
    }
}
#endif
