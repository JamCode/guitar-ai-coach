import SwiftUI

/// 在宿主 `TabView` 中，push 出的子页默认仍会显示底部 TabBar；用该容器包一层目标页，
/// 通过 `.toolbar(.hidden, for: .tabBar)` 达到类似微信「仅根 Tab 显示底栏」的效果。
///
/// 这里**不使用** `onAppear` / `@State` 去切换可见性：那样会在 pop 时与导航移除子视图
/// 差一帧，根页 `GeometryReader` 等会先按「无底栏」尺寸摆一帧再缩回，产生跳变。
/// 静态 modifier 随子页进栈挂载、出栈移除，与 TabBar 显隐同一套布局事务更新。
public struct TabBarHiddenContainer<Content: View>: View {
    @ViewBuilder public var content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        #if os(iOS)
        content()
            .toolbar(.hidden, for: .tabBar)
        #else
        content()
        #endif
    }
}
