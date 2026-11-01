//
//  OnboardingViewModel.swift
//  GFPriceChecker
//
//  Created by Claude Code on 2026-11-01.
//

import Foundation
import Observation

/// Which page the onboarding sheet is on.
///
/// Lifted out of `OnboardingView`'s private `@State` so a demo script can turn
/// the pages: the site's onboarding slides are cut from `DemoScripts`'
/// `onboarding` script, which writes `page` the way the other scripts write
/// their screens' view models.
@Observable
final class OnboardingViewModel {

    /// The pages, in order. `OnboardingView` tags each page with its case.
    enum Page: Int, CaseIterable {
        case welcome
        case howItWorks
        case smartScanning
        case camera
        case ready
    }

    var page: Page = .welcome

    var isFirstPage: Bool { page == .welcome }

    var isLastPage: Bool { page == Page.allCases.last }

    /// Moves to the next page, and does nothing on the last.
    func next() {
        guard let following = Page(rawValue: page.rawValue + 1) else { return }
        page = following
    }

    /// Moves to the previous page, and does nothing on the first.
    func back() {
        guard let previous = Page(rawValue: page.rawValue - 1) else { return }
        page = previous
    }
}
