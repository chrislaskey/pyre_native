import SwiftUI

struct NotFoundView: View {
    @EnvironmentObject var router: URLRouter
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 30) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 80))
                    .foregroundColor(.orange)
                    .padding(.top, 40)
                
                VStack(spacing: 10) {
                    Text("Page Not Found")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("The page you're looking for doesn't exist or you don't have permission to view it.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Button("Go Home") {
                    let redirectPath = RouterHelpers.getHomePath()
                    router.navigate(to: redirectPath)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Spacer()
            }
            .padding()
        }
    }
}

