//

struct BinaryDependencies: Decodable {
	let `public`: [PublicBinaryLib]
	let `private`: [PrivateBinaryLib]
}
