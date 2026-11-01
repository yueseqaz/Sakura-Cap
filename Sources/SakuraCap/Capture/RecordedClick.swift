import CoreGraphics

/// 录制期间记录的一次点击：time 为视频内时间（暂停段已剔除，与成片时间轴对齐）；
/// point 为点击在画面中的归一化位置（左上原点 0–1），与 WorkbenchFocus.rect 同坐标系。
struct RecordedClick: Equatable {
    let time: Double
    let point: CGPoint
}
