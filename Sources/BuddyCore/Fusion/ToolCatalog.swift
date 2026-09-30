import Foundation

/// 工具归类（DESIGN.md「工具归类」）。输入可以是被 hook 截断过的名字（结尾带 `…`）。
public enum ToolCatalog {
    /// 去掉 hook 截断留下的 `…`（U+2026）以及首尾空白。
    public static func cleanName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("…") { s.removeLast() }
        return s
    }

    /// `mcp__<server>__<tool>` 里的 server；不是 mcp 名字返回 nil。
    /// 截断名字（例如 `mcp__ccd_session_mgmt__search_session_tr`）也能取到 server。
    public static func mcpServer(of name: String) -> String? {
        let n = cleanName(name)
        guard n.hasPrefix("mcp__") else { return nil }
        let rest = n.dropFirst(5)
        if let r = rest.range(of: "__") { return String(rest[rest.startIndex..<r.lowerBound]) }
        return rest.isEmpty ? nil : String(rest)
    }

    public static func category(of rawName: String) -> ToolCategory {
        let name = cleanName(rawName)
        switch name {
        case "Read", "NotebookRead": return .read
        case "Grep", "Glob", "LS": return .search
        case "Edit", "MultiEdit": return .edit
        case "Write", "NotebookEdit": return .write
        // TaskOutput / TaskStop 是新版本里 BashOutput / KillShell 的新名字（真实日志里见到过 TaskStop）
        case "Bash", "BashOutput", "KillShell", "TaskOutput", "TaskStop": return .bash
        case "Monitor": return .monitor
        case "WebFetch", "WebSearch": return .web
        case "Agent", "Task", "Workflow", "SendMessage": return .delegate
        case "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet": return .todo
        case "Skill", "ToolSearch", "ListSkills": return .skill
        case "EnterPlanMode": return .planEnter
        case "ExitPlanMode": return .planExit
        case "SendUserFile": return .sendFile
        // —— Codex（OpenAI）的工具名：exec / exec_command 是执行 shell（exec 是包了一层 JS 的写法）、apply_patch 改文件、
        //    view_image 看图、js 是 computer-use 的 REPL、collaboration 系列是派子代理 ——
        case "exec", "exec_command", "write_stdin", "shell", "local_shell", "container.exec": return .bash
        case "apply_patch": return .edit
        case "view_image": return .read
        case "js": return .computer
        case "web_search": return .web
        case "update_plan": return .todo
        case "tool_search": return .skill
        case "spawn_agent", "wait_agent", "send_message", "followup_task", "list_agents", "interrupt_agent", "close_agent", "resume_agent": return .delegate
        case "ScheduleWakeup", "CronCreate", "CronDelete", "CronList": return .schedule
        default: break
        }
        if name.hasPrefix("mcp__Claude_Browser__") || name.hasPrefix("mcp__claude-in-chrome__") { return .browser }
        if name.hasPrefix("mcp__computer-use__") { return .computer }
        if name.hasPrefix("mcp__") { return .mcp }
        return .unknown
    }

    /// 由名字直接构造 ToolCall（server 自动填）。
    public static func makeCall(name rawName: String, detail: String = "", at: Date) -> ToolCall {
        let name = cleanName(rawName)
        let cat = category(of: name)
        let server: String? = (cat == .mcp || cat == .browser || cat == .computer) ? mcpServer(of: name) : nil
        return ToolCall(name: name, category: cat, detail: detail, server: server, startedAt: at)
    }
}
