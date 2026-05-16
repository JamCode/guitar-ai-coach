import Foundation

/// 写入本地练习记录的最低前台时长：低于该秒数的会话不落库（次数与总时长均不计）。
public enum PracticeRecordingPolicy {
    public static let minForegroundSecondsToPersist: Int = 30
}
