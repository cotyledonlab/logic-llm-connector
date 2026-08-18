public enum CompanionSocketPath {
    public static func `default`(userID: UInt32) -> String {
        "/tmp/logic-llm-connector-\(userID).sock"
    }
}
