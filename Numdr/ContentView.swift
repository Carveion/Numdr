import SwiftUI
import Combine
import UniformTypeIdentifiers
import PDFKit
import CoreText

// MARK: - Models
struct HistoryItem: Identifiable, Codable {
    let id: UUID
    let fileName: String
    let filePath: String
    let date: Date
}

enum NavigationItem: String, CaseIterable {
    case home = "Home"
    case history = "History"
    case settings = "Settings"
    
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .history: return "clock.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Custom Colors
extension Color {
    static let mainCream = Color(red: 0.98, green: 0.97, blue: 0.95)
    static let darkCream = Color(red: 0.92, green: 0.90, blue: 0.85)
    static let darkBeige = Color(red: 0.55, green: 0.48, blue: 0.38)
    static let classicBlue = Color(red: 0.0, green: 0.35, blue: 0.85)
}

// MARK: - View Model
class NumdrViewModel: ObservableObject {
    @Published var selectedFileURL: URL?
    @Published var isProcessing = false
    @Published var statusMessage: String?
    @Published var isSuccess = false
    
    // Settings
    @Published var position: PagePosition = .bottomRight
    @Published var alternateSides = false
    @Published var fontSize: CGFloat = 14
    @Published var isBold = false
    @Published var isItalic = false
    @Published var isUnderline = false
    
    // UI States
    @Published var showImporter = false
    @Published var isHoveringDrop = false
    @Published var selectedNav: NavigationItem? = .home
    
    // Data
    @Published var history: [HistoryItem] = []
    @Published var defaultSaveDirectory: URL?
    
    enum PagePosition: String, CaseIterable {
        case topLeft = "Top Left"
        case topCenter = "Top Center"
        case topRight = "Top Right"
        case bottomLeft = "Bottom Left"
        case bottomCenter = "Bottom Center"
        case bottomRight = "Bottom Right"
    }
    
    init() {
        loadHistory()
        loadDefaultDirectory()
    }
    
    func selectFile() { showImporter = true }
    
    func processPDF() {
        guard let inputURL = selectedFileURL else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType.pdf]
        savePanel.nameFieldStringValue = inputURL.deletingPathExtension().lastPathComponent + "_numbered.pdf"
        if let dir = defaultSaveDirectory { savePanel.directoryURL = dir }
        
        savePanel.begin { [weak self] result in
            if result == .OK, let outputURL = savePanel.url {
                self?.addPageNumbers(inputURL: inputURL, outputURL: outputURL)
            }
        }
    }
    
    private func addPageNumbers(inputURL: URL, outputURL: URL) {
        isProcessing = true
        statusMessage = "Processing PDF..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            let success = PDFProcessor.addPageNumbers(
                inputURL: inputURL, outputURL: outputURL, position: self.position,
                alternateSides: self.alternateSides, fontSize: self.fontSize,
                isBold: self.isBold, isItalic: self.isItalic, isUnderline: self.isUnderline
            )
            
            DispatchQueue.main.async {
                self.isProcessing = false
                self.isSuccess = success
                self.statusMessage = success ? "Successfully saved!" : "Failed to process PDF."
                if success {
                    self.addToHistory(url: outputURL)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.statusMessage = nil }
                }
            }
        }
    }
    
    private func addToHistory(url: URL) {
        let item = HistoryItem(id: UUID(), fileName: url.lastPathComponent, filePath: url.path, date: Date())
        history.insert(item, at: 0)
        saveHistory()
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "NumdrHistory")
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "NumdrHistory"),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            self.history = decoded
        }
    }
    
    func clearHistory() { history.removeAll(); saveHistory() }
    
    func revealInFinder(filePath: String) {
        let url = URL(fileURLWithPath: filePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    func chooseDefaultDirectory() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.prompt = "Set Default Folder"
        openPanel.begin { [weak self] result in
            if result == .OK, let url = openPanel.url {
                self?.defaultSaveDirectory = url
                UserDefaults.standard.set(url.path, forKey: "NumdrDefaultSavePath")
            }
        }
    }
    
    private func loadDefaultDirectory() {
        if let path = UserDefaults.standard.string(forKey: "NumdrDefaultSavePath") {
            self.defaultSaveDirectory = URL(fileURLWithPath: path)
        }
    }
}

// MARK: - Main Layout View
struct ContentView: View {
    @StateObject private var viewModel = NumdrViewModel()
    
    var body: some View {
        NavigationSplitView {
            List(NavigationItem.allCases, id: \.self, selection: $viewModel.selectedNav) { item in
                HStack {
                    Image(systemName: item.icon).frame(width: 20)
                    Text(item.rawValue).font(.system(size: 14, weight: .medium))
                }
                .padding(.vertical, 4)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 200)
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
            
        } detail: {
            ZStack {
                Color.mainCream.ignoresSafeArea()
                
                switch viewModel.selectedNav {
                case .home, .none: HomeView(viewModel: viewModel)
                case .history: HistoryView(viewModel: viewModel)
                case .settings: SettingsView(viewModel: viewModel)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 650)
    }
}

// MARK: - Home View
struct HomeView: View {
    @ObservedObject var viewModel: NumdrViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // FIX: Placed the entire header INSIDE the ScrollView so nothing cuts off abruptly
            ScrollView {
                VStack(spacing: 25) {
                    
                    // Header
                    VStack(spacing: 6) {
                        Text("Numdr.")
                            .font(.system(size: 48, weight: .black, design: .default))
                            .foregroundColor(.black)
                        
                        Text("(Mac-powered PDF numberer)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black.opacity(0.5))
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 10)
                    
                    DropZoneView(viewModel: viewModel)
                    
                    if viewModel.selectedFileURL != nil {
                        SettingsPanelView(viewModel: viewModel)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            
            // Bottom Action Area
            VStack(spacing: 12) {
                if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.callout.bold())
                        .foregroundColor(viewModel.isSuccess ? .green : .red)
                        .animation(.easeInOut, value: viewModel.statusMessage)
                }
                
                Button(action: { viewModel.processPDF() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(viewModel.selectedFileURL == nil || viewModel.isProcessing ? Color.black.opacity(0.1) : Color.black)
                        
                        HStack {
                            if viewModel.isProcessing {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "doc.badge.plus")
                            }
                            Text(viewModel.isProcessing ? "Processing..." : "Add Page Numbers")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(viewModel.selectedFileURL == nil || viewModel.isProcessing ? .black.opacity(0.3) : .white)
                    }
                    .frame(height: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.selectedFileURL == nil || viewModel.isProcessing)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .fileImporter(
            isPresented: $viewModel.showImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                withAnimation(.spring()) {
                    viewModel.selectedFileURL = urls.first
                }
            }
        }
    }
}

// MARK: - Animated Document Icon Fix
struct AnimatedSuccessIcon: View {
    @State private var isHovering = false
    
    var body: some View {
        ZStack {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 38))
                .foregroundColor(.green)
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.white)
                .background(Circle().fill(Color.green))
                .offset(x: 14, y: 14)
        }
        .offset(y: isHovering ? -6 : 0) // Smooth bobbing
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isHovering = true
            }
        }
    }
}

// MARK: - Custom UI Components
struct DropZoneView: View {
    @ObservedObject var viewModel: NumdrViewModel
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.darkCream)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            viewModel.isHoveringDrop ? Color.black : Color.black.opacity(0.08),
                            style: StrokeStyle(lineWidth: 2, dash: [8])
                        )
                )
            
            VStack(spacing: 12) {
                if viewModel.selectedFileURL == nil {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.black.opacity(0.6))
                } else {
                    AnimatedSuccessIcon() // Safe, guaranteed-to-animate icon
                }
                
                if let url = viewModel.selectedFileURL {
                    Text(url.lastPathComponent)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    Text("Click to change file")
                        .font(.caption)
                        .foregroundColor(.black.opacity(0.5))
                } else {
                    Text("Drag & Drop your PDF here")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                    Text("or click to browse")
                        .font(.caption)
                        .foregroundColor(.black.opacity(0.5))
                }
            }
            .padding(40)
            .contentShape(Rectangle())
        }
        .frame(height: 160)
        .onTapGesture { viewModel.selectFile() }
        .onDrop(of: [.pdf], isTargeted: $viewModel.isHoveringDrop) { providers in
            if let provider = providers.first {
                provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { item, _ in
                    if let url = item as? URL {
                        DispatchQueue.main.async {
                            withAnimation(.spring()) {
                                viewModel.selectedFileURL = url
                            }
                        }
                    }
                }
                return true
            }
            return false
        }
    }
}

// FIX: New Grid Position Picker
struct PositionButton: View {
    let title: String
    let position: NumdrViewModel.PagePosition
    @Binding var selection: NumdrViewModel.PagePosition
    
    var isSelected: Bool { selection == position }
    
    var body: some View {
        Button(action: { selection = position }) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? Color.classicBlue : Color.white.opacity(0.8))
                .foregroundColor(isSelected ? .white : .black)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.classicBlue : Color.black.opacity(0.1), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsPanelView: View {
    @ObservedObject var viewModel: NumdrViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Configuration")
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(.darkBeige)
            
            // Positioning Grid (Replaced Dropdown)
            VStack(alignment: .leading, spacing: 16) {
                Text("Position").font(.subheadline).bold().foregroundColor(.black)
                
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        PositionButton(title: "Top Left", position: .topLeft, selection: $viewModel.position)
                        PositionButton(title: "Top Center", position: .topCenter, selection: $viewModel.position)
                        PositionButton(title: "Top Right", position: .topRight, selection: $viewModel.position)
                    }
                    HStack(spacing: 8) {
                        PositionButton(title: "Bottom Left", position: .bottomLeft, selection: $viewModel.position)
                        PositionButton(title: "Bottom Center", position: .bottomCenter, selection: $viewModel.position)
                        PositionButton(title: "Bottom Right", position: .bottomRight, selection: $viewModel.position)
                    }
                }
                
                Divider().opacity(0.5).padding(.vertical, 4)
                
                Toggle(isOn: $viewModel.alternateSides) {
                    Text("Alternate sides for facing pages")
                        .font(.subheadline.bold())
                        .foregroundColor(.black)
                }
                .toggleStyle(.switch)
                .tint(.classicBlue)
            }
            .padding(20)
            .background(Color.darkCream)
            .cornerRadius(16)
            
            // Typography
            VStack(alignment: .leading, spacing: 16) {
                Text("Typography")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.darkBeige)
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Size: \(Int(viewModel.fontSize))")
                            .font(.subheadline)
                            .foregroundColor(.black)
                            .frame(width: 60, alignment: .leading)
                        Slider(value: $viewModel.fontSize, in: 8...36, step: 1)
                            .tint(.classicBlue)
                    }
                    
                    HStack(spacing: 15) {
                        StyleButton(title: "B", isSelected: $viewModel.isBold, font: .system(size: 16, weight: .bold))
                        StyleButton(title: "I", isSelected: $viewModel.isItalic, font: .system(size: 16).italic())
                        StyleButton(title: "U", isSelected: $viewModel.isUnderline, font: .system(size: 16))
                            .underline()
                    }
                }
                .padding(20)
                .background(Color.darkCream)
                .cornerRadius(16)
            }
        }
    }
}

struct StyleButton: View {
    let title: String
    @Binding var isSelected: Bool
    let font: Font
    
    var body: some View {
        Button(action: { isSelected.toggle() }) {
            Text(title)
                .font(font)
                .frame(width: 36, height: 36)
                .background(isSelected ? Color.classicBlue : Color.white.opacity(0.8))
                .foregroundColor(isSelected ? .white : .black)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.classicBlue : Color.black.opacity(0.1), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History & Settings Views
struct HistoryView: View {
    @ObservedObject var viewModel: NumdrViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("History")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(.black)
                Spacer()
                if !viewModel.history.isEmpty {
                    Button("Clear History") { viewModel.clearHistory() }
                    .buttonStyle(.link)
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            
            if viewModel.history.isEmpty {
                Spacer()
                Text("No previously numbered files yet.")
                    .font(.headline)
                    .foregroundColor(.black.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                List(viewModel.history) { item in
                    HStack {
                        Image(systemName: "doc.pdf.fill")
                            .foregroundColor(.black.opacity(0.7))
                            .font(.system(size: 24))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.fileName).font(.headline).foregroundColor(.black)
                            Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundColor(.black.opacity(0.5))
                        }
                        
                        Spacer()
                        
                        Button(action: { viewModel.revealInFinder(filePath: item.filePath) }) {
                            Text("Reveal in Finder")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.classicBlue) // accent blue
                                .foregroundColor(.white)       // readable on blue
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .onHover { if $0 { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 24)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: NumdrViewModel
    
    var body: some View {
        VStack(alignment: .center, spacing: 40) {
            VStack(spacing: 12) {
                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                
                Text("Numdr.")
                    .font(.system(size: 32, weight: .black))
                    .foregroundColor(.black)
                Text("Version 1.0")
                    .font(.headline)
                    .foregroundColor(.black.opacity(0.5))
            }
            .padding(.top, 60)
            
            VStack(alignment: .leading, spacing: 15) {
                Text("Preferences").font(.system(size: 14, weight: .heavy)).foregroundColor(.darkBeige)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Default Save Directory").font(.subheadline.bold()).foregroundColor(.black)
                    HStack {
                        Text(viewModel.defaultSaveDirectory?.path ?? "System Default (Downloads/Documents)")
                            .lineLimit(1).truncationMode(.middle)
                            .font(.system(size: 13)).foregroundColor(.black.opacity(0.7))
                            .padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.8)).cornerRadius(8)
                        
                        Button(action: { viewModel.chooseDefaultDirectory() }) {
                            Text("Choose Folder...")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(Color.classicBlue).foregroundColor(.white).cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20).background(Color.darkCream).cornerRadius(16)
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Footer: By / Carveion Inc.
            VStack(spacing: 2) {
                Text("Carveion Inc.")
                    .font(.custom("Futura", size: 12))
                    .foregroundColor(.black.opacity(0.5))
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Utilities & PDF Processor
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct PDFProcessor {
    static func addPageNumbers(
        inputURL: URL, outputURL: URL, position: NumdrViewModel.PagePosition,
        alternateSides: Bool, fontSize: CGFloat, isBold: Bool, isItalic: Bool, isUnderline: Bool
    ) -> Bool {
        guard let pdf = PDFDocument(url: inputURL) else { return false }
        guard let context = CGContext(outputURL as CFURL, mediaBox: nil, nil) else { return false }
        
        let pageCount = pdf.pageCount
        for i in 0..<pageCount {
            guard let page = pdf.page(at: i) else { continue }
            var mediaBox = page.bounds(for: .mediaBox)
            context.beginPage(mediaBox: &mediaBox)
            page.draw(with: .mediaBox, to: context)
            
            let text = "\(i + 1)"
            var font = NSFont.systemFont(ofSize: fontSize)
            var traits: NSFontTraitMask = []
            if isBold { traits.insert(.boldFontMask) }
            if isItalic { traits.insert(.italicFontMask) }
            if !traits.isEmpty { font = NSFontManager.shared.convert(font, toHaveTrait: traits) }
            
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            if isUnderline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            
            let attributedString = NSAttributedString(string: text, attributes: attributes)
            let textSize = attributedString.size()
            
            var currentPosition = position
            if alternateSides && (i % 2 == 1) {
                switch position {
                case .topLeft: currentPosition = .topRight
                case .topRight: currentPosition = .topLeft
                case .bottomLeft: currentPosition = .bottomRight
                case .bottomRight: currentPosition = .bottomLeft
                default: break
                }
            }
            
            let margin: CGFloat = 36.0
            var x: CGFloat = 0, y: CGFloat = 0
            
            switch currentPosition {
            case .topLeft: x = margin; y = mediaBox.height - margin - textSize.height
            case .topCenter: x = (mediaBox.width - textSize.width) / 2; y = mediaBox.height - margin - textSize.height
            case .topRight: x = mediaBox.width - margin - textSize.width; y = mediaBox.height - margin - textSize.height
            case .bottomLeft: x = margin; y = margin
            case .bottomCenter: x = (mediaBox.width - textSize.width) / 2; y = margin
            case .bottomRight: x = mediaBox.width - margin - textSize.width; y = margin
            }
            
            context.saveGState()
            let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
            let path = CGPath(rect: CGRect(x: x, y: y, width: textSize.width + 10, height: textSize.height + 10), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributedString.length), path, nil)
            CTFrameDraw(frame, context)
            context.restoreGState()
            context.endPage()
        }
        context.closePDF()
        return true
    }
}
