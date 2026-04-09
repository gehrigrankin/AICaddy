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
        ScrollView {
            VStack(spacing: 16) {
                // Mode toggle
                if !existingCourses.isEmpty {
                    Picker("Mode", selection: $mode) {
                        Text("Saved Course").tag(SetupMode.select)
                        Text("New Course").tag(SetupMode.create)
                    }
                    .pickerStyle(.segmented)
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

    // MARK: - Select existing

    private var selectCourseView: some View {
        VStack(spacing: 12) {
            ForEach(existingCourses, id: \.id) { course in
                Button {
                    selectedCourse = course
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name).font(.subheadline.bold())
                            Text("Tees: \(course.tees.map(\.name).joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedCourse?.id == course.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .padding(12)
                    .background(selectedCourse?.id == course.id ? Color.green.opacity(0.1) : Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selectedCourse?.id == course.id ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                }
            }

            if let course = selectedCourse {
                // Tee picker
                if course.tees.count > 1 {
                    Picker("Tee", selection: $teeName) {
                        ForEach(course.tees, id: \.name) { tee in
                            Text(tee.name).tag(tee.name)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Button {
                    let tee = teeName.isEmpty ? (course.tees.first?.name ?? "Default") : teeName
                    onComplete(course, tee)
                } label: {
                    Text("Start Round")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: - Create new

    private var createCourseView: some View {
        VStack(spacing: 16) {
            TextField("Course name", text: $courseName)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 8) {
                VStack(alignment: .leading) {
                    Text("Tee").font(.caption).foregroundStyle(.secondary)
                    TextField("White", text: $teeName)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading) {
                    Text("Rating").font(.caption).foregroundStyle(.secondary)
                    TextField("72.1", text: $courseRating)
                        .textFieldStyle(.plain)
                        .keyboardType(.decimalPad)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading) {
                    Text("Slope").font(.caption).foregroundStyle(.secondary)
                    TextField("131", text: $slope)
                        .textFieldStyle(.plain)
                        .keyboardType(.numberPad)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            // Quick presets
            HStack(spacing: 8) {
                Text("Quick set:").font(.caption).foregroundStyle(.secondary)
                ForEach([3, 4, 5], id: \.self) { p in
                    Button("All \(p)") {
                        holes = holes.map { var h = $0; h.par = p; return h }
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // Hole list
            ForEach($holes) { $hole in
                HStack(spacing: 8) {
                    Text("\(hole.number)")
                        .font(.subheadline.bold())
                        .frame(width: 24)
                        .foregroundStyle(.secondary)

                    // Par picker
                    ForEach([3, 4, 5], id: \.self) { p in
                        Button {
                            hole.par = p
                        } label: {
                            Text("\(p)")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(hole.par == p ? Color.green : Color(.systemGray5))
                                .foregroundStyle(hole.par == p ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    TextField("yds", text: $hole.yardageText)
                        .textFieldStyle(.plain)
                        .keyboardType(.numberPad)
                        .frame(width: 56)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // Total par
            Text("Total Par: \(holes.reduce(0) { $0 + $1.par })")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                createAndStart()
            } label: {
                Text("Start Round")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(courseName.isEmpty ? Color.green.opacity(0.5) : Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(courseName.trimmingCharacters(in: .whitespaces).isEmpty)
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
