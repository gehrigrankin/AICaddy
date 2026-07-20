import SwiftUI
import CoreLocation

struct CourseSearchView: View {
    let courseSearch: CourseSearchService
    let locationService: LocationService
    let onCourseLoaded: (Course) -> Void
    let onCourseWithTeeLoaded: ((Course, String) -> Void)?
    let onSkip: () -> Void
    /// Previously-played courses — one tap to start, no network needed.
    let recentCourses: [Course]
    let onRecentCourseSelected: ((Course) -> Void)?

    @State private var query = ""
    @State private var results: [CourseSearchResult] = []
    @State private var searching = false
    @State private var loadingId: String?
    @State private var error: String?
    @State private var loadedCourse: Course?
    @State private var showTeeSelection = false

    init(courseSearch: CourseSearchService, locationService: LocationService,
         onCourseLoaded: @escaping (Course) -> Void,
         onCourseWithTeeLoaded: ((Course, String) -> Void)? = nil,
         onSkip: @escaping () -> Void,
         recentCourses: [Course] = [],
         onRecentCourseSelected: ((Course) -> Void)? = nil) {
        self.courseSearch = courseSearch
        self.locationService = locationService
        self.onCourseLoaded = onCourseLoaded
        self.onCourseWithTeeLoaded = onCourseWithTeeLoaded
        self.onSkip = onSkip
        self.recentCourses = recentCourses
        self.onRecentCourseSelected = onRecentCourseSelected
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.Colors.backdrop, Theme.Colors.surfaceDeep, Theme.Colors.backdrop],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 4) {
                        Text("SELECT COURSE")
                            .font(Theme.Font.display(24))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .tracking(2)
                        Text("SEARCH FOR A COURSE TO LOAD GPS DATA")
                            .font(Theme.Font.caption(10))
                            .foregroundStyle(Theme.Colors.textMuted)
                            .tracking(1)
                    }
                    .padding(.top, 12)

                    HStack(spacing: 8) {
                        TextField("", text: $query, prompt: Text("Course name…").foregroundColor(Theme.Colors.textMuted))
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
                            .submitLabel(.search)
                            .onSubmit { searchByName() }

                        Button { searchByName() } label: {
                            Text(searching ? "..." : "SEARCH")
                                .font(Theme.Font.title(13))
                                .tracking(1)
                                .foregroundStyle(Theme.Colors.backdrop)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                        .fill(Theme.Colors.accent)
                                )
                        }
                        .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    Button { searchNearby() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 13, weight: .heavy))
                            Text(searching ? "FINDING COURSES..." : "FIND COURSES NEAR ME")
                                .font(Theme.Font.title(13))
                                .tracking(1)
                        }
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .fill(Theme.Colors.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .strokeBorder(Theme.Colors.border, lineWidth: 1)
                        )
                    }
                    .disabled(searching)

                    // Recent courses — play again without searching
                    if !recentCourses.isEmpty && results.isEmpty && !searching {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RECENT COURSES")
                                .font(Theme.Font.caption(10))
                                .foregroundStyle(Theme.Colors.textMuted)
                                .tracking(1)

                            ForEach(recentCourses, id: \.id) { course in
                                Button { onRecentCourseSelected?(course) } label: {
                                    HStack {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.system(size: 14, weight: .heavy))
                                            .foregroundStyle(Theme.Colors.accent)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(course.name.uppercased())
                                                .font(Theme.Font.title(14))
                                                .foregroundStyle(Theme.Colors.textPrimary)
                                                .tracking(0.5)
                                            if let city = course.city {
                                                Text(city.uppercased())
                                                    .font(Theme.Font.caption(10))
                                                    .foregroundStyle(Theme.Colors.textMuted)
                                                    .tracking(0.5)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .heavy))
                                            .foregroundStyle(Theme.Colors.textMuted)
                                    }
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                            .fill(Theme.Colors.surface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                            .strokeBorder(Theme.Colors.accent.opacity(0.25), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !results.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(results.count) RESULT\(results.count == 1 ? "" : "S")")
                                .font(Theme.Font.caption(10))
                                .foregroundStyle(Theme.Colors.textMuted)
                                .tracking(1)

                            ForEach(results) { result in
                                Button { loadCourse(result) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(result.name.uppercased())
                                                .font(Theme.Font.title(14))
                                                .foregroundStyle(Theme.Colors.textPrimary)
                                                .tracking(0.5)
                                            if let city = result.city, let state = result.state {
                                                Text("\(city), \(state)".uppercased())
                                                    .font(Theme.Font.caption(10))
                                                    .foregroundStyle(Theme.Colors.textMuted)
                                                    .tracking(0.5)
                                            }
                                        }
                                        Spacer()
                                        if loadingId == result.id {
                                            ProgressView().tint(Theme.Colors.accent)
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12, weight: .heavy))
                                                .foregroundStyle(Theme.Colors.textMuted)
                                        }
                                    }
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
                                .buttonStyle(.plain)
                                .disabled(loadingId != nil)
                            }
                        }
                    }

                    if let error {
                        Text(error.uppercased())
                            .font(Theme.Font.caption(10))
                            .foregroundStyle(Theme.Colors.negative)
                            .tracking(0.5)
                            .multilineTextAlignment(.center)
                    }

                    Spacer(minLength: 20)

                    Button { onSkip() } label: {
                        Text("SET UP COURSE MANUALLY")
                            .font(Theme.Font.caption(11))
                            .foregroundStyle(Theme.Colors.textMuted)
                            .tracking(1)
                    }
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 18)
            }
        }
        .sheet(isPresented: $showTeeSelection) {
            if let course = loadedCourse {
                teeSelectionSheet(course)
            }
        }
    }

    private func searchByName() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true
        error = nil
        results = []

        Task {
            do {
                let found = try await courseSearch.searchByName(query)
                await MainActor.run {
                    results = found
                    if found.isEmpty { error = "No courses found. Try a different name." }
                    searching = false
                }
            } catch let searchError {
                await MainActor.run {
                    self.error = searchError.localizedDescription
                    searching = false
                }
            }
        }
    }

    private func searchNearby() {
        searching = true
        error = nil
        results = []

        guard let loc = locationService.location else {
            locationService.requestPermission()
            error = "Enable location access to search nearby."
            searching = false
            return
        }

        Task {
            do {
                let found = try await courseSearch.searchNearby(lat: loc.latitude, lng: loc.longitude)
                await MainActor.run {
                    results = found
                    if found.isEmpty { error = "No courses found nearby." }
                    searching = false
                }
            } catch let searchError {
                await MainActor.run {
                    self.error = searchError.localizedDescription
                    searching = false
                }
            }
        }
    }

    private func loadCourse(_ result: CourseSearchResult) {
        loadingId = result.id
        error = nil

        Task {
            do {
                let details = try await courseSearch.fetchCourseDetails(id: result.id)
                let course = Course(
                    id: result.id,
                    name: details.name,
                    city: details.city,
                    state: details.state,
                    location: details.location,
                    tees: details.tees
                )
                await MainActor.run {
                    loadingId = nil
                    if course.tees.count > 1 && onCourseWithTeeLoaded != nil {
                        loadedCourse = course
                        showTeeSelection = true
                    } else {
                        onCourseLoaded(course)
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to load course details"
                    loadingId = nil
                }
            }
        }
    }

    private func teeSelectionSheet(_ course: Course) -> some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backdrop.ignoresSafeArea()
                VStack(spacing: 14) {
                    VStack(spacing: 4) {
                        Text("SELECT TEES")
                            .font(Theme.Font.display(20))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .tracking(1.5)
                        Text(course.name.uppercased())
                            .font(Theme.Font.caption(11))
                            .foregroundStyle(Theme.Colors.textMuted)
                            .tracking(1)
                    }
                    .padding(.top, 12)

                    ForEach(course.tees) { tee in
                        Button {
                            showTeeSelection = false
                            onCourseWithTeeLoaded?(course, tee.name)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tee.name.uppercased())
                                        .font(Theme.Font.title(15))
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .tracking(1)
                                    if let rating = tee.rating, let slope = tee.slope {
                                        Text("RATING \(String(format: "%.1f", rating)) · SLOPE \(slope)")
                                            .font(Theme.Font.caption(10))
                                            .foregroundStyle(Theme.Colors.textMuted)
                                            .tracking(0.5)
                                    }
                                    if let totalYardage = tee.holes.compactMap(\.yardage).reduce(0, +) as Int?,
                                       totalYardage > 0 {
                                        Text("\(totalYardage) YARDS")
                                            .font(Theme.Font.caption(10))
                                            .foregroundStyle(Theme.Colors.accent)
                                            .tracking(0.5)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
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
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showTeeSelection = false
                        loadedCourse = nil
                    } label: {
                        Text("CANCEL")
                            .font(Theme.Font.caption(12))
                            .foregroundStyle(Theme.Colors.accent)
                            .tracking(1)
                    }
                }
            }
            .toolbarBackground(Theme.Colors.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}
