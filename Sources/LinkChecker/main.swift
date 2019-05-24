import CommonMark
import Foundation

let markdown = #"""
- [objc.io](https://www.objc.io)
- [local](#local)
- [401](http://httpstat.us/401)
- [timeout](http://httpstat.us/200?sleep=30000)
"""#

let rootNode = Node(markdown: markdown)
var collectLinks: BlockAlgebra<[String]> = collect()
collectLinks.inline.link = { _, _, url in url.map { [$0] } ?? [] }
let links = rootNode.reduce(collectLinks)
let urls = links.compactMap(URL.init)

struct UnknownError: Error {}

struct LinkCheckResult {
    var url: URL
    var error: Error?
}

final class Atomic<A> {
    private let queue = DispatchQueue(label: "Atomic serial queue")
    private var _value: A
    
    init(_ value: A) {
        self._value = value
    }
    
    var value: A {
        get { return queue.sync { self._value } }
    }
    
    func mutate(_ transform: (inout A) -> ()) {
        queue.sync { transform(&self._value) }
    }
}

extension URLSession {
    func check(urls: [URL], callback: @escaping (LinkCheckResult) -> (), done: @escaping () -> ()) {
        let remaining: Atomic<Set<URL>> = Atomic(Set(urls))
        for url in remaining.value {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 2
            dataTask(with: request) { (data, response, error) in
                let h = response.flatMap { $0 as? HTTPURLResponse }
                if h?.statusCode == 200 {
                    callback(LinkCheckResult(url: url, error: nil))
                } else {
                    callback(LinkCheckResult(url: url, error: error ?? UnknownError()))
                }
                remaining.mutate {
                    $0.remove(url)
                }
                if remaining.value.isEmpty {
                    done()
                }
            }.resume()
        }
    }
}

let group = DispatchGroup()
group.enter()
URLSession.shared.check(urls: urls, callback: { result in
    print(result)
}, done: {
    group.leave()
})
group.wait()
print("Link checking done")
