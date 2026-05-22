import SwiftData
import Foundation

/// Seeds the 6 built-in agents on first launch. Idempotent — skips if already seeded.
struct AgentSeeder {

    static func seedIfNeeded(context: ModelContext) {
        // Fetch which template agents already exist by name so we never duplicate.
        // This is robust against store wipes, schema migrations, and manual deletions.
        let existingNames: Set<String>
        do {
            let existing = try context.fetch(
                FetchDescriptor<Agent>(predicate: #Predicate { $0.isTemplate == true })
            )
            existingNames = Set(existing.map { $0.name })
        } catch {
            existingNames = []
        }

        let missing = builtInAgents().filter { !existingNames.contains($0.name) }
        guard !missing.isEmpty else { return }

        for agent in missing {
            context.insert(agent)
        }

        do {
            try context.save()
        } catch {
            NSLog("AgentSeeder: failed to save — \(error)")
        }
    }

    // MARK: - Built-in agents

    private static func builtInAgents() -> [Agent] {
        [
            morningBriefing(),
            emailDigest(),
            meetingPrep(),
            weeklyWrap(),
            smartReplyDrafter(),
            folderSummariser()
        ]
    }

    // 1. Morning Briefing
    private static func morningBriefing() -> Agent {
        let agent = Agent(
            name: "Morning Briefing",
            description: "A daily brief covering your schedule, emails, and news.",
            icon: "sunrise",
            isTemplate: true
        )

        var calStep = AgentStep(order: 0, stepType: .readCalendar, label: "Today's events")
        var calConfig = CalendarStepConfig()
        calConfig.rangeType = .today
        calStep.encodeConfig(calConfig)

        var mailStep = AgentStep(order: 1, stepType: .readMail, label: "Unread emails")
        var mailConfig = MailStepConfig()
        mailConfig.dateRangeHours = 24
        mailConfig.unreadOnly = true
        mailStep.encodeConfig(mailConfig)

        var rssStep = AgentStep(order: 2, stepType: .readRSS, label: "News feeds")
        let rssConfig = RSSStepConfig()
        rssStep.encodeConfig(rssConfig)

        var thinkStep = AgentStep(order: 3, stepType: .think, label: "Write briefing")
        var thinkConfig = ThinkStepConfig()
        thinkConfig.systemPrompt = "You are a helpful assistant creating a morning briefing. Be concise and friendly."
        thinkConfig.userPromptTemplate = """
Today's calendar events:
{step_0_output}

Recent emails:
{step_1_output}

News:
{step_2_output}

Write a concise morning briefing covering: schedule highlights, emails needing attention, and interesting news. Use clear headings.
"""
        thinkStep.encodeConfig(thinkConfig)

        var outputStep = AgentStep(order: 4, stepType: .output, label: "Show briefing")
        var outputConfig = OutputStepConfig()
        outputConfig.format = .markdown
        outputStep.encodeConfig(outputConfig)

        agent.steps = [calStep, mailStep, rssStep, thinkStep, outputStep]
        return agent
    }

    // 2. Email Digest
    private static func emailDigest() -> Agent {
        let agent = Agent(
            name: "Email Digest",
            description: "Summarise your inbox and flag items needing a reply.",
            icon: "envelope.badge",
            isTemplate: true
        )

        var mailStep = AgentStep(order: 0, stepType: .readMail, label: "Recent emails")
        var mailConfig = MailStepConfig()
        mailConfig.dateRangeHours = 48
        mailConfig.maxItems = 30
        mailConfig.unreadOnly = true
        mailStep.encodeConfig(mailConfig)

        var thinkStep = AgentStep(order: 1, stepType: .think, label: "Summarise inbox")
        var thinkConfig = ThinkStepConfig()
        thinkConfig.systemPrompt = "You are an email assistant. Summarise emails clearly and identify which need a reply."
        thinkConfig.userPromptTemplate = """
Here are my recent emails:
{step_0_output}

Please:
1. Group by sender or topic
2. Flag any that need a reply
3. Highlight anything urgent

Keep it concise.
"""
        thinkStep.encodeConfig(thinkConfig)

        var outputStep = AgentStep(order: 2, stepType: .output, label: "Show digest")
        var outputConfig = OutputStepConfig()
        outputConfig.format = .markdown
        outputStep.encodeConfig(outputConfig)

        agent.steps = [mailStep, thinkStep, outputStep]
        return agent
    }

    // 3. Meeting Prep
    private static func meetingPrep() -> Agent {
        let agent = Agent(
            name: "Meeting Prep",
            description: "Get context and talking points before your next meeting.",
            icon: "person.2",
            isTemplate: true
        )

        var calStep = AgentStep(order: 0, stepType: .readCalendar, label: "Next meeting")
        var calConfig = CalendarStepConfig()
        calConfig.rangeType = .nextNDays
        calConfig.rangeDays = 1
        calStep.encodeConfig(calConfig)

        var mailStep = AgentStep(order: 1, stepType: .readMail, label: "Related emails")
        var mailConfig = MailStepConfig()
        mailConfig.dateRangeHours = 168
        mailStep.encodeConfig(mailConfig)

        var thinkStep = AgentStep(order: 2, stepType: .think, label: "Prepare notes")
        var thinkConfig = ThinkStepConfig()
        thinkConfig.systemPrompt = "You are a meeting prep assistant. Help the user walk into their next meeting well-prepared."
        thinkConfig.userPromptTemplate = """
Upcoming meeting:
{step_0_output}

Recent related emails:
{step_1_output}

Create a brief meeting prep document covering:
- Who is attending and what they care about
- Key topics likely to come up
- Questions worth asking
- Any open items from email threads
"""
        thinkStep.encodeConfig(thinkConfig)

        var outputStep = AgentStep(order: 3, stepType: .output, label: "Show prep notes")
        var outputConfig = OutputStepConfig()
        outputConfig.format = .markdown
        outputStep.encodeConfig(outputConfig)

        agent.steps = [calStep, mailStep, thinkStep, outputStep]
        return agent
    }

    // 4. Weekly Wrap
    private static func weeklyWrap() -> Agent {
        let agent = Agent(
            name: "Weekly Wrap",
            description: "A summary of your week — what happened and what's still open.",
            icon: "calendar.badge.checkmark",
            isTemplate: true
        )

        var calStep = AgentStep(order: 0, stepType: .readCalendar, label: "This week's events")
        var calConfig = CalendarStepConfig()
        calConfig.rangeType = .lastNDays
        calConfig.rangeDays = 7
        calStep.encodeConfig(calConfig)

        var mailStep = AgentStep(order: 1, stepType: .readMail, label: "This week's emails")
        var mailConfig = MailStepConfig()
        mailConfig.dateRangeHours = 168
        mailConfig.unreadOnly = false
        mailConfig.maxItems = 50
        mailStep.encodeConfig(mailConfig)

        var thinkStep = AgentStep(order: 2, stepType: .think, label: "Write weekly wrap")
        var thinkConfig = ThinkStepConfig()
        thinkConfig.systemPrompt = "You are a personal assistant writing a weekly review. Be warm and practical."
        thinkConfig.userPromptTemplate = """
This week's calendar events:
{step_0_output}

This week's emails:
{step_1_output}

Write a weekly wrap covering:
- Key things that happened this week
- Decisions made or progress on projects
- Things still open or needing follow-up
- A brief reflection on how the week went
"""
        thinkStep.encodeConfig(thinkConfig)

        var outputStep = AgentStep(order: 3, stepType: .output, label: "Show wrap")
        var outputConfig = OutputStepConfig()
        outputConfig.format = .markdown
        outputStep.encodeConfig(outputConfig)

        agent.steps = [calStep, mailStep, thinkStep, outputStep]
        return agent
    }

    // 5. Smart Reply Drafter
    private static func smartReplyDrafter() -> Agent {
        let agent = Agent(
            name: "Smart Reply Drafter",
            description: "Paste an email and get three reply options to choose from.",
            icon: "arrowshape.turn.up.left",
            isTemplate: true
        )

        var thinkStep = AgentStep(order: 0, stepType: .think, label: "Draft replies")
        var thinkConfig = ThinkStepConfig()
        thinkConfig.systemPrompt = "You are an email writing assistant. Write in a clear, professional but warm tone."
        thinkConfig.userPromptTemplate = """
Here is the email I need to reply to:

{user_input}

Please write three different reply options:
1. **Brief** — 2-3 sentences, gets straight to the point
2. **Detailed** — thorough response that covers everything
3. **Warm** — friendly and personable tone

Format each option clearly with a label.
"""
        thinkStep.encodeConfig(thinkConfig)

        var outputStep = AgentStep(order: 1, stepType: .output, label: "Show drafts")
        var outputConfig = OutputStepConfig()
        outputConfig.format = .markdown
        outputConfig.copyToClipboard = false
        outputStep.encodeConfig(outputConfig)

        agent.steps = [thinkStep, outputStep]
        return agent
    }

    // 6. Folder Summariser
    private static func folderSummariser() -> Agent {
        let agent = Agent(
            name: "Folder Summariser",
            description: "Point it at a folder and get a summary of everything inside.",
            icon: "folder.badge.questionmark",
            isTemplate: true
        )

        var filesStep = AgentStep(order: 0, stepType: .readFiles, label: "Read folder")
        let filesConfig = FilesStepConfig()
        filesStep.encodeConfig(filesConfig)

        var thinkStep = AgentStep(order: 1, stepType: .think, label: "Summarise contents")
        var thinkConfig = ThinkStepConfig()
        thinkConfig.systemPrompt = "You are a document assistant. Summarise files clearly and extract key information."
        thinkConfig.userPromptTemplate = """
Here are the files in the folder:
{step_0_output}

Please provide:
1. An overview of what this folder contains
2. A summary of each document's key content
3. Any action items or important information extracted from the documents
"""
        thinkStep.encodeConfig(thinkConfig)

        var outputStep = AgentStep(order: 2, stepType: .output, label: "Show summary")
        var outputConfig = OutputStepConfig()
        outputConfig.format = .markdown
        outputStep.encodeConfig(outputConfig)

        agent.steps = [filesStep, thinkStep, outputStep]
        return agent
    }
}
