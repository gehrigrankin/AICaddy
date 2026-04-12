import SwiftUI

struct CourseSetupView: View {
    let onComplete: (Course, String) -> Void
    let existingCourses: [Course]

    @State private var mode: SetupMode = .create
    @State private var courseName = ""
    @State private var teeName = "White"
    @State private var courseRating = ""
    @State private var slope = ""
    @State private var holes: [EditableHole] = (1...18).map { EditableHole(number: $0) }
    @State private var selectedCourse: Course?

    enum SetupMode { case select, create }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.Colors.backdrop, Theme.Colors.surfaceDeep, Theme.Colors.backdrop],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    if !existingCourses.isEmpty {
                        Picker("Mode", selection: $mode) {
                            Text("SAVED").tag(SetupMode.select)
                            Text("NEW").tag(SetupMode.create)
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 8)
                    }

                    if mode == .select && !existingCourses.isEmpty {
                        selectCourseView
                    } else {
                        createCourseView
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Select existing

    private var selectCourseView: some View {
        VStack(spacing: 12) {
            ForEach(existingCourses, id: \.id) { course in
                let isSelected = selectedCourse?.id == course.id
                Button { selectedCourse = course } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(course.name.uppercased())
                                .font(Theme.Font.title(14))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .tracking(0.5)
                            Text("TEES: \(course.tees.map(\.name).joined(separator: ", ").uppercased())")
                                .font(Theme.Font.caption(10))
                                .foregroundStyle(Theme.Colors.textMuted)
                                .tracking(0.5)
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(isSelected ? Theme.Colors.accentSoft : Theme.Colors.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(isSelected ? Theme.Colors.accent.opacity(0.5) : Theme.Colors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if let course = selectedCourse {
                if course.tees.count > 1 {
                    Picker("Tee", selection: $teeName) {
                        ForEach(course.tees, id: \.name) { tee in
                            Text(tee.name.uppercased()).tag(tee.name)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                startRoundButton(enabled: true) {
                    let tee = teeName.isEmpty ? (course.tees.first?.name ?? "Default") : teeName
                    onComplete(course, tee)
                }
            }
        }
    }

    // MARK: - Create new

    private var createCourseView: some View {
        VStack(spacing: 14) {
            themeField(placeholder: "Course name", text: $courseName)

            HStack(spacing: 8) {
                labeledField(label: "TEE", placeholder: "White", text: $teeName)
                labeledField(label: "RATING", placeholder: "72.1", text: $courseRating, keyboard: .decimalPad)
                labeledField(label: "SLOPE", placeholder: "131", text: $slope, keyboard: .numberPad)
            }

            HStack(spacing: 8) {
                Text("QUICK SET")
                    .font(Theme.Font.caption(10))
                    .foregroundStyle(Theme.Colors.textMuted)
                    .tracking(1)
                ForEach([3, 4, 5], id: \.self) { p in
                    Button {
                        holes = holes.map { var h = $0; h.par = p; return h }
                    } label: {
                        Text("ALL \(p)")
                            .font(Theme.Font.caption(11))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .tracking(0.5)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Theme.Colors.surfaceElevated)
                            )
                            .overlay(Capsule().strokeBorder(Theme.Colors.border, lineWidth: 1))
                    }
                }
                Spacer()
            }

            ForEach($holes) { $hole in
                HStack(spacing: 8) {
                    Text("\(hole.number)")
                        .font(Theme.Font.title(13))
                        .foregroundStyle(Theme.Colors.textMuted)
                        .frame(width: 24)

                    ForEach([3, 4, 5], id: \.self) { p in
                        let isSelected = hole.par == p
                        Button { hole.par = p } label: {
                            Text("\(p)")
                                .font(Theme.Font.title(13))
                                .foregroundStyle(isSelected ? Theme.Colors.backdrop : Theme.Colors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                                        .fill(isSelected ? Theme.Colors.accent : Theme.Colors.surfaceElevated)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                                        .strokeBorder(isSelected ? Theme.Colors.accent : Theme.Colors.border, lineWidth: 1)
                                )
                        }
                    }

                    TextField("", text: $hole.yardageText, prompt: Text("yds").foregroundColor(Theme.Colors.textMuted))
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tint(Theme.Colors.accent)
                        .keyboardType(.numberPad)
                        .frame(width: 56)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                                .fill(Theme.Colors.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                                .strokeBorder(Theme.Colors.border, lineWidth: 1)
                        )
                }
            }

            Text("TOTAL PAR: \(holes.reduce(0) { $0 + $1.par })")
                .font(Theme.Font.caption(11))
                .foregroundStyle(Theme.Colors.textMuted)
                .tracking(1)

            startRoundButton(enabled: !courseName.trimmingCharacters(in: .whitespaces).isEmpty) {
                createAndStart()
            }
        }
    }

    // MARK: - Helpers

    private func startRoundButton(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("START ROUND")
                .font(Theme.Font.title(15))
                .tracking(1.5)
                .foregroundStyle(Theme.Colors.backdrop)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(enabled ? Theme.Colors.accent : Theme.Colors.accent.opacity(0.4))
                )
                .themeShadow(ShadowStyle(color: Theme.Colors.accent.opacity(enabled ? 0.3 : 0), radius: 12, x: 0, y: 5))
        }
        .disabled(!enabled)
    }

    private func themeField(placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(Theme.Colors.textMuted))
            .textFieldStyle(.plain)
            .foregroundStyle(Theme.Colors.textPrimary)
            .tint(Theme.Colors.accent)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Colors.border, lineWidth: 1)
            )
    }

    private func labeledField(label: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Font.caption(9))
                .foregroundStyle(Theme.Colors.textMuted)
                .tracking(1)
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(Theme.Colors.textMuted))
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tint(Theme.Colors.accent)
                .keyboardType(keyboard)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                        .fill(Theme.Colors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                        .strokeBorder(Theme.Colors.border, lineWidth: 1)
                )
        }
    }

    private func createAndStart() {
        let courseHoles = holes.map { h in
            CourseHoleData(
                holeNumber: h.number,
                par: h.par,
                yardage: Int(h.yardageText)
            )
        }

        let tee = CourseTee(
            name: teeName.isEmpty ? "Default" : teeName,
            rating: Double(courseRating),
            slope: Int(slope),
            holes: courseHoles
        )

        let course = Course(
            name: courseName.trimmingCharacters(in: .whitespaces),
            tees: [tee]
        )

        onComplete(course, tee.name)
    }
}

struct EditableHole: Identifiable {
    let id = UUID()
    let number: Int
    var par: Int = 4
    var yardageText: String = ""
}
