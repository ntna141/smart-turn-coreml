import SwiftUI
import UniformTypeIdentifiers

struct TranscriptionView: View {

    @State private var viewModel = TranscriptionViewModel()
    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    statusCard
                    if viewModel.isReady {
                        actionButtons
                        diagnosticsCard
                    }
                    if !viewModel.transcriptionText.isEmpty {
                        resultsCard
                    }
                    if let error = viewModel.errorMessage {
                        errorCard(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Parakeet v3")
            .task {
                if !viewModel.isReady {
                    await viewModel.loadModels()
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await viewModel.transcribeFile(url: url) }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        VStack(spacing: 12) {
            switch viewModel.state {
            case .idle:
                if viewModel.isReady {
                    Label("Models Loaded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                } else {
                    Label("Not Loaded", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                        .font(.headline)
                    Button("Load Models") {
                        Task { await viewModel.loadModels() }
                    }
                    .buttonStyle(.borderedProminent)
                }

            case .downloading(let progress):
                VStack(spacing: 8) {
                    Label("Downloading Models...", systemImage: "arrow.down.circle")
                        .font(.headline)
                    ProgressView(value: progress)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .loadingModels:
                VStack(spacing: 8) {
                    Label("Compiling Models...", systemImage: "gearshape.2")
                        .font(.headline)
                    ProgressView()
                }

            case .recording:
                VStack(spacing: 8) {
                    Label("Recording...", systemImage: "mic.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Button("Stop & Transcribe") {
                        Task { await viewModel.stopRecordingAndTranscribe() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

            case .transcribing:
                VStack(spacing: 8) {
                    Label("Transcribing...", systemImage: "waveform")
                        .font(.headline)
                    ProgressView()
                }

            case .pickingFile:
                Label("Select a file...", systemImage: "doc")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                Task { await viewModel.startRecording() }
            } label: {
                Label("Record", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.state != .idle)

            Button {
                showFilePicker = true
            } label: {
                Label("Pick File", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.state != .idle)
        }
    }

    @ViewBuilder
    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Live Turn Detection")
                .font(.headline)

            HStack {
                metric("Speech", value: viewModel.isSpeaking ? "Speaking" : "Silent")
                Spacer()
                metric("VAD", value: String(format: "%.1f%%", viewModel.vadConfidence * 100))
            }

            Text(viewModel.turnStatus)
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription")
                .font(.headline)

            Text(viewModel.transcriptionText)
                .font(.body)
                .textSelection(.enabled)

            Divider()

            HStack {
                metric("Duration", value: String(format: "%.2fs", viewModel.duration))
                Spacer()
                metric("Processing", value: String(format: "%.2fs", viewModel.processingTime))
                Spacer()
                metric("RTFx", value: String(format: "%.1fx", viewModel.rtfx))
                Spacer()
                metric("Confidence", value: String(format: "%.1f%%", viewModel.confidence * 100))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.monospacedDigit().bold())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
