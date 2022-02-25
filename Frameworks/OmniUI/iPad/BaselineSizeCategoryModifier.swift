// Copyright 2021-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import OmniFoundation
import SwiftUI

/// This steps your environment's content up or down relative to the default content size. If the system is set to the .large content size and you supply the `.large` content size as the baseline, this view modifier will step the content of the modified view up to the `.extraLarge` content size. This is useful in situation where you want a specific font size at the default setting, but still want it to scale when the system size is changed. For example, 17 point system font is equivalent to the `.footnote` semantic font size in the `.extraExtraLarge` size category. So, by modifying a view given the `baselineSizeCategory` of `.extraExtraLarge` and using the `.footnote` font in it, you will get 17 point system font at the default size category. If the system content size is set to `.large`, this modifier will render the `.footnote` text at its size in the `.extraExtraExtraLarge` size category.
public struct BaselineSizeCategoryModifier: OUIViewModifier {

    public let baselineSizeCategory: ContentSizeCategory?
    @Environment(\.sizeCategory) var sizeCategory
    
    public init(baselineSizeCategory: ContentSizeCategory?) {
        self.baselineSizeCategory = baselineSizeCategory
    }

    public func oui_body(content: Self.Content) -> some View {
        content
            .equatableEnvironment(\EnvironmentValues.sizeCategory, usedSizeCategory)
    }
    
    private var usedSizeCategory: ContentSizeCategory {
        if let baselineSizeCategory = baselineSizeCategory {
            return sizeCategory.adjustedSize(for: baselineSizeCategory)
        } else {
            return sizeCategory
        }
    }
}

extension View {
    public func baselineSizeCategory(_ sizeCategory: ContentSizeCategory) -> some View {
        modifier(BaselineSizeCategoryModifier(baselineSizeCategory: sizeCategory))
    }
}

public extension ContentSizeCategory {
    
    static var `default`: ContentSizeCategory = .large
    
    func adjustedSize(for baselineSize: ContentSizeCategory) -> ContentSizeCategory {
        return step(sizesUp: baselineSize.distanceFromRegular)
    }
    
    private func step(sizesUp: Int) -> ContentSizeCategory {
        let allSizes = ContentSizeCategory.allCases
        let currentCategoryIndex = allSizes.firstIndex(of: self)!
        if let foundSize = allSizes[safe: currentCategoryIndex + sizesUp] {
            return foundSize
        } else if sizesUp > 0 {
            return allSizes.last!
        } else {
            return allSizes.first!
        }
    }
    
    private var distanceFromRegular: Int {
        switch self {
        case .extraSmall: return -3
        case .small: return -2
        case .medium: return -1
        case .large: return 0 // Large is the default setting on iOS.
        case .extraLarge: return 1
        case .extraExtraLarge: return 2
        case .extraExtraExtraLarge: return 3
        case .accessibilityMedium: return 4
        case .accessibilityLarge: return 5
        case .accessibilityExtraLarge: return 6
        case .accessibilityExtraExtraLarge: return 7
        case .accessibilityExtraExtraExtraLarge: return 8
        default: return 0
        }
    }
}

#if os(iOS)
public extension UIContentSizeCategory {
    @available(iOSApplicationExtension 14.0, *)
    func adjustedSize(for baselineSize: UIContentSizeCategory) -> UIContentSizeCategory {
        return UIContentSizeCategory(contentSizeCategory.adjustedSize(for: baselineSize.contentSizeCategory))
    }
    
    static var `default`: UIContentSizeCategory = .large
    
    private var contentSizeCategory: ContentSizeCategory {
        switch self {
        case .extraSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .extraLarge: return .extraLarge
        case .extraExtraLarge: return .extraExtraLarge
        case .extraExtraExtraLarge: return .extraExtraExtraLarge
        case .accessibilityMedium: return .accessibilityMedium
        case .accessibilityLarge: return .accessibilityLarge
        case .accessibilityExtraLarge: return .accessibilityExtraLarge
        case .accessibilityExtraExtraLarge: return .accessibilityExtraExtraLarge
        case .accessibilityExtraExtraExtraLarge: return .accessibilityExtraExtraExtraLarge
        default: return .medium
        }
    }
    
    private init(from swiftUICategory: ContentSizeCategory) {
        switch swiftUICategory {
        case .extraSmall: self = .extraSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .extraLarge: self = .extraLarge
        case .extraExtraLarge: self = .extraExtraLarge
        case .extraExtraExtraLarge: self = .extraExtraExtraLarge
        case .accessibilityMedium: self = .accessibilityMedium
        case .accessibilityLarge: self = .accessibilityLarge
        case .accessibilityExtraLarge: self = .accessibilityExtraLarge
        case .accessibilityExtraExtraLarge: self = .accessibilityExtraExtraLarge
        case .accessibilityExtraExtraExtraLarge: self = .accessibilityExtraExtraExtraLarge
        default: self = .medium
        }
    }
}
#endif
