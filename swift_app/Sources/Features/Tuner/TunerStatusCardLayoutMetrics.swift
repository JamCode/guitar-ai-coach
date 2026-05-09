import Core
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 与 `TunerStatusCardBody` 中「最坏情况」一致的文案，用于布局高度估算（随当前语言）。
enum TunerStatusLayoutWorstCase {
    static var helper: String {
        "\(AppL10n.t("tuner_state_need_helper"))\n\(AppL10n.t("tuner_state_pluck_helper"))"
    }

    static var title: String { AppL10n.t("tuner_state_pluck_title") }
    static var detail: String { AppL10n.t("tuner_state_pluck_detail") }
    static var targetCaption: String {
        String(format: AppL10n.t("tuner_target_line_format"), Int64(1), "329.63")
    }

    static var rotation: String {
        String(format: AppL10n.t("tuner_rot_loose_fmt"), AppL10n.t("tuner_knob_right"))
    }
}

/// 在已知内容宽度下，用文本排版引擎估算「最坏文案」撑满后的高度，与 SwiftUI 卡片内层对齐。
enum TunerStatusCardLayoutMetrics {
    /// `contentInnerWidth`：状态区内层可用宽度（已扣掉 `appCard` 左右各 14）。
    static func estimatedWorstCaseHeight(contentInnerWidth: CGFloat) -> CGFloat {
        let w = max(80, contentInnerWidth)
        #if canImport(UIKit)
        return estimatedHeightUIKit(innerWidth: w)
        #elseif canImport(AppKit)
        return estimatedHeightAppKit(innerWidth: w)
        #else
        return 308
        #endif
    }

    #if canImport(UIKit)
    private static func estimatedHeightUIKit(innerWidth: CGFloat) -> CGFloat {
        let spacing: CGFloat = 10
        let titleColumn: CGFloat = 148
        let hStackGap: CGFloat = 16
        let rightW = max(56, innerWidth - titleColumn - hStackGap)

        var y: CGFloat = 0
        y += measureUIKit(text: AppL10n.t("tuner_section_status"), width: innerWidth, font: .systemFont(ofSize: 15, weight: .semibold), maxLines: 1)
        y += spacing
        y += measureUIKit(
            text: TunerStatusLayoutWorstCase.helper,
            width: innerWidth,
            font: .preferredFont(forTextStyle: .caption1),
            maxLines: 2
        )
        y += spacing

        let titleFont = UIFont.systemFont(ofSize: 42, weight: .bold)
        let titleH = ceil((TunerStatusLayoutWorstCase.title as NSString).size(withAttributes: [.font: titleFont]).height)

        let detailFont = UIFont.preferredFont(forTextStyle: .body)
        let footFont = UIFont.preferredFont(forTextStyle: .footnote)
        let centsFont = UIFont.preferredFont(forTextStyle: .body)
        let d1 = measureUIKit(text: TunerStatusLayoutWorstCase.detail, width: rightW, font: detailFont, maxLines: 3)
        let d2 = measureUIKit(text: TunerStatusLayoutWorstCase.targetCaption, width: rightW, font: footFont, maxLines: 2)
        let d3 = measureUIKit(text: String(format: AppL10n.t("tuner_cents_format"), -50.0), width: rightW, font: centsFont, maxLines: 1)
        let rightH = d1 + 4 + d2 + 4 + d3
        y += max(titleH, rightH)
        y += spacing

        y += measureUIKit(
            text: TunerStatusLayoutWorstCase.rotation,
            width: innerWidth,
            font: .preferredFont(forTextStyle: .caption1),
            maxLines: 5
        )
        y += spacing
        y += 20
        y += 18
        return ceil(y)
    }

    private static func measureUIKit(text: String, width: CGFloat, font: UIFont, maxLines: Int) -> CGFloat {
        let ps = NSMutableParagraphStyle()
        ps.lineBreakMode = .byWordWrapping
        let attr = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: ps])
        let rect = attr.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let h = ceil(rect.height)
        let cap = ceil(font.lineHeight * CGFloat(maxLines) + max(0, font.leading))
        return min(h, cap)
    }
    #endif

    #if canImport(AppKit) && !canImport(UIKit)
    private static func estimatedHeightAppKit(innerWidth: CGFloat) -> CGFloat {
        let spacing: CGFloat = 10
        let titleColumn: CGFloat = 148
        let hStackGap: CGFloat = 16
        let rightW = max(56, innerWidth - titleColumn - hStackGap)

        var y: CGFloat = 0
        y += measureAppKit(text: AppL10n.t("tuner_section_status"), width: innerWidth, font: .systemFont(ofSize: 15, weight: .semibold), maxLines: 1)
        y += spacing
        y += measureAppKit(text: TunerStatusLayoutWorstCase.helper, width: innerWidth, font: .systemFont(ofSize: 12), maxLines: 2)
        y += spacing

        let titleFont = NSFont.systemFont(ofSize: 42, weight: .bold)
        let titleH = ceil((TunerStatusLayoutWorstCase.title as NSString).size(withAttributes: [.font: titleFont]).height)

        let d1 = measureAppKit(text: TunerStatusLayoutWorstCase.detail, width: rightW, font: .systemFont(ofSize: 17), maxLines: 3)
        let d2 = measureAppKit(text: TunerStatusLayoutWorstCase.targetCaption, width: rightW, font: .systemFont(ofSize: 13), maxLines: 2)
        let d3 = measureAppKit(text: String(format: AppL10n.t("tuner_cents_format"), -50.0), width: rightW, font: .systemFont(ofSize: 17), maxLines: 1)
        let rightH = d1 + 4 + d2 + 4 + d3
        y += max(titleH, rightH)
        y += spacing
        y += measureAppKit(text: TunerStatusLayoutWorstCase.rotation, width: innerWidth, font: .systemFont(ofSize: 12), maxLines: 5)
        y += spacing
        y += 20
        y += 18
        return ceil(y)
    }

    private static func measureAppKit(text: String, width: CGFloat, font: NSFont, maxLines: Int) -> CGFloat {
        let ps = NSMutableParagraphStyle()
        ps.lineBreakMode = .byWordWrapping
        let attr = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: ps])
        let rect = attr.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let h = ceil(rect.height)
        let line = font.ascender - font.descender + font.leading
        let cap = ceil(line * CGFloat(maxLines))
        return min(h, cap)
    }
    #endif
}
