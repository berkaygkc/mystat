import Metal
import MystatTestSupport
import Testing
@testable import MystatUI

@Suite(.language("tr")) struct ShaderCompileTests {
    @Test func shaderCompiles() throws {
        let d = try #require(MTLCreateSystemDefaultDevice())
        let lib = try d.makeLibrary(source: BubbleShaderSource.msl, options: nil)
        #expect(lib.makeFunction(name: "bubbleFragment") != nil)
        #expect(lib.makeFunction(name: "fullscreenVertex") != nil)
    }
    @Test func uniformLayoutSize() {
        #expect(BubbleShaderSource.uniformVectorCount == 176)   // 8 başlık + 24×3 + 96
    }
}
