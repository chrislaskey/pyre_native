import SwiftUI

struct UnauthorizedView: View {
    @EnvironmentObject var router: URLRouter
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 30) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 80))
                    .foregroundColor(.orange)
                    .padding(.top, 40)
                
                VStack(spacing: 10) {
                    Text("Not Authorized")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("You need to be logged in to view this page.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Button("Go to Log In") {
                    let redirectPath = RouterHelpers.getSignInPath()
                    router.navigate(to: redirectPath)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
    }
}

