import SwiftUI
import Combine

// MARK: - Rolling Number Animation View

/// A SwiftUI view that animates number changes with a rolling effect
struct RollingNumberView: View {
    @Binding var value: Double
    let formatter: NumberFormatter
    private let animationDuration: Double = 0.8
    
    @State private var displayValue: Double = 0.0
    @State private var isAnimating: Bool = false
    
    init(value: Binding<Double>, formatter: NumberFormatter = defaultCurrencyFormatter()) {
        self._value = value
        self.formatter = formatter
    }
    
    var body: some View {
        Text(formattedValue)
            .font(.system(.body, design: .monospaced))
            .lineLimit(1)
            .fixedSize()
            .onAppear {
                displayValue = value
            }
            .onChange(of: value) { oldValue, newValue in
                animateToNewValue(from: oldValue, to: newValue)
            }
    }
    
    private var formattedValue: String {
        return formatter.string(from: NSNumber(value: displayValue)) ?? "$0.00"
    }
    
    private func animateToNewValue(from oldValue: Double, to newValue: Double) {
        guard oldValue != newValue else { return }
        
        isAnimating = true
        
        let steps = 30
        let increment = (newValue - oldValue) / Double(steps)
        let stepDuration = animationDuration / Double(steps)
        
        for i in 1...steps {
            let delay = Double(i - 1) * stepDuration
            let targetValue = oldValue + (increment * Double(i))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: stepDuration)) {
                    self.displayValue = targetValue
                }
                
                if i == steps {
                    self.isAnimating = false
                }
            }
        }
    }
    
    private static func defaultCurrencyFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }
}

// MARK: - NSView Wrapper for Menu Bar

/// NSView wrapper for the rolling number animation to be used in NSStatusItem
class RollingNumberNSView: NSView {
    private let textField: NSTextField
    private let formatter: NumberFormatter
    private var currentValue: Double = 0.0
    private var displayValue: Double = 0.0
    private var isAnimating: Bool = false
    private let animationDuration: Double = 0.8
    
    init(formatter: NumberFormatter = defaultCurrencyFormatter()) {
        self.formatter = formatter
        self.textField = NSTextField()
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        self.formatter = Self.defaultCurrencyFormatter()
        self.textField = NSTextField()
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        // Configure text field
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBordered = false
        textField.backgroundColor = NSColor.clear
        textField.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textField.alignment = .center
        textField.stringValue = formatter.string(from: NSNumber(value: displayValue)) ?? "$0.00"
        
        addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // Set initial size
        invalidateIntrinsicContentSize()
    }
    
    func updateValue(_ newValue: Double) {
        guard newValue != currentValue else { return }
        
        let oldValue = currentValue
        currentValue = newValue
        
        // If not animating, start animation
        if !isAnimating {
            animateToNewValue(from: oldValue, to: newValue)
        }
    }
    
    private func animateToNewValue(from oldValue: Double, to newValue: Double) {
        guard oldValue != newValue else { return }
        
        isAnimating = true
        
        let steps = 30
        let increment = (newValue - oldValue) / Double(steps)
        let stepDuration = animationDuration / Double(steps)
        
        for i in 1...steps {
            let delay = Double(i - 1) * stepDuration
            let targetValue = oldValue + (increment * Double(i))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                
                self.displayValue = targetValue
                self.textField.stringValue = self.formatter.string(from: NSNumber(value: targetValue)) ?? "$0.00"
                
                if i == steps {
                    self.isAnimating = false
                }
            }
        }
    }
    
    override var intrinsicContentSize: NSSize {
        // Calculate size based on formatted text
        let sampleText = formatter.string(from: NSNumber(value: 999.99)) ?? "$999.99"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ]
        let size = sampleText.size(withAttributes: attributes)
        return NSSize(width: size.width + 8, height: size.height + 4) // Add padding
    }
    
    private static func defaultCurrencyFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }
}

// MARK: - Preview

#if DEBUG
struct RollingNumberView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapper()
            .frame(width: 200, height: 100)
            .padding()
    }
}

private struct PreviewWrapper: View {
    @State private var testValue: Double = 27.69
    
    var body: some View {
        VStack(spacing: 20) {
            RollingNumberView(value: $testValue)
            
            Button("Change Value") {
                testValue = Double.random(in: 0...100)
            }
        }
    }
}
#endif