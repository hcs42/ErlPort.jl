# Copyright (c) 2014, Dreki Þórgísl <dreki@billo.systems>
#               2014, Bence Golda <bence@cursorinsight.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#  * Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#  * Neither the name of the copyright holders nor the names of its
#    contributors may be used to endorse or promote products derived from this
#    software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
module Decode

using ErlPort.Exceptions

export decode, decodeterm, decodeatom,
decodesmallint, decodeint, decodenewfloat,
decodesmallbigint, decodelargebigint,
decodebin,
decodenil, decodestring, decodelist,
decodesmalltuple, decodelargetuple,
decompressterm,
size1unpack, size2unpack, size4unpack # for tests only XXX: do we really need this here?

include("Tags.jl")
include("Util.jl")

function decode(bytes::Array{Uint8,1})
    lencheck(bytes, 1)
    if bytes[1] != version
        throw(UnknownProtocolVersion(bytes[1]))
    end
    if length(bytes) >= 2 && bytes[2] == compressedtag
        # XXX maybe have this match the call to decode below? bytes[2:end]
        # instead of just bytes?
        return decodeterm(decompressterm(bytes))
    end
    return decodeterm(bytes[2:end])
end

function decode(unsupported)
    throw(UnsupportedType(unsupported))
end

function decodeterm(bytes::Array{Uint8,1})
    lencheck(bytes, 1)
    tag = bytes[1]
    if tag == atomtag
        return decodeatom(bytes)
    elseif tag == niltag
        return decodenil(bytes)
    elseif tag == stringtag
        return decodestring(bytes)
    elseif tag == smalltupletag
        return decodesmalltuple(bytes)
    elseif tag == largetupletag
        return decodelargetuple(bytes)
    elseif tag == listtag
        return decodelist(bytes)
    elseif tag == smallinttag
        return decodesmallint(bytes)
    elseif tag == inttag
        return decodeint(bytes)
    elseif tag == bintag
        return decodebin(bytes)
    elseif tag == newfloattag
        return decodenewfloat(bytes)
    elseif tag == smallbiginttag
        return decodesmallbigint(bytes)
    elseif tag == largebiginttag
        return decodelargebigint(bytes)
    else
        throw(UnsupportedData(bytes))
    end
end

function decodeterm(acc::Array, byte::Uint8)
    vcat(acc, decodeterm([byte]))
end

function decodeatom(bytes::Array{Uint8,1})
    len = lencheck(bytes, 3)
    unpackedlen = lencheck(len, size2unpack(bytes[2:3]) + 3, bytes)
    name = bytes[4:unpackedlen]
    if name == b"true"
        return (true, bytes[unpackedlen+1:end])
    elseif name == b"false"
        return (false, bytes[unpackedlen+1:end])
    elseif name == b"undefined"
        return (nothing, bytes[unpackedlen+1:end])
    else
        return (symbol(name), bytes[unpackedlen+1:end])
    end
end

function decodenil(bytes::Array{Uint8,1})
    lencheck(bytes, 1)
    return ([], bytes[2:end])
end

function decodestring(bytes::Array{Uint8,1})
    len = lencheck(bytes, 3)
    unpackedlen = lencheck(len, size2unpack(bytes[2:3]) + 3, bytes)
    (bytes[4:unpackedlen], bytes[unpackedlen+1:end])
end

function decodesmallint(bytes::Array{Uint8,1})
    lencheck(bytes, 2)
    (int1unpack(bytes[2]), bytes[3:end])
end

function decodeint(bytes::Array{Uint8,1})
    lencheck(bytes, 5)
    (int4unpack(bytes[2:5]), bytes[6:end])
end

function decodebin(bytes::Array{Uint8,1})
    len = lencheck(bytes, 5)
    unpackedlen = lencheck(len, size4unpack(bytes[2:5]) + 5, bytes)
    (bytes[6:unpackedlen], bytes[unpackedlen+1:end])
end

function decodenewfloat(bytes::Array{Uint8,1})
    lencheck(bytes, 9)
    (floatunpack(bytes[2:9]), bytes[10:end])
end

function decodelist(bytes::Array{Uint8,1})
    lencheck(bytes, 5)
    (results, tail) = converttoarray(size4unpack(bytes[2:5]), bytes[6:end])
    # XXX mojombo's BERT (https://github.com/mojombo/bert) does the same -- it
    # skips the improper part in lists (or throws a RuntimeError)
    (skipped, tail) = decodeterm(tail)
    (results, tail)
end

function converttoarray(len::Uint64, tail::Array{Uint8,1})
    results = map([0:1:len-1]) do i
        (term, tail) = decodeterm(tail)
        term
    end
    (results, tail)
end

function decodesmalltuple(bytes::Array{Uint8,1})
    lencheck(bytes, 2)
    converttotuple(size1unpack(bytes[2]), bytes[3:end])
end

function decodelargetuple(bytes::Array{Uint8,1})
    lencheck(bytes, 5)
    converttotuple(size4unpack(bytes[2:5]), bytes[6:end])
end

function converttotuple(len::Uint64, tail::Array{Uint8,1})
    if len < 1
        return( (), tail )
    end
    (results, tail) = converttoarray(len, tail)
    (tuple(results...), tail)
end

function decodesmallbigint(bytes::Array{Uint8,1})
    len = lencheck(bytes, 3)
    bisize = size1unpack(bytes[2])
    lencheck(len, bisize + 3, bytes)
    result = computebigint(bisize, bytes[4:bisize+3], bytes[3])
    (result, bytes[bisize+4:end])
end

function decodelargebigint(bytes::Array{Uint8,1})
    len = lencheck(bytes, 6)
    bisize = size4unpack(bytes[2:5])
    lencheck(len, bisize + 6, bytes)
    result = computebigint(bisize, bytes[7:bisize+6], bytes[6])
    (result, bytes[bisize+7:end])
end

function computebigint(len::Uint64, coefficients::Array{Uint8,1}, sign::Uint8)
    result = sum((256 .^ [0:len-1]) .* convert(Array{Int}, coefficients))
    return(sign > 0 ? -result : result)
end

end
