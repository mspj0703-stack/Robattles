--!strict
-- 최소 데이터 검증 라이브러리. 외부 패키지 없이 RemoteEvent 페이로드와 데이터 테이블을 검증한다.
-- validate(spec, value) -> (ok, errorMessage?)

export type Spec = { kind: string, [string]: any }

local Schema = {}

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

function Schema.number(opts: { min: number?, max: number?, integer: boolean? }?): Spec
	local o: { min: number?, max: number?, integer: boolean? } = opts or {}
	return { kind = "number", min = o.min, max = o.max, integer = o.integer }
end

function Schema.integer(min: number?, max: number?): Spec
	return { kind = "number", min = min, max = max, integer = true }
end

function Schema.boolean(): Spec
	return { kind = "boolean" }
end

function Schema.string(maxLength: number?): Spec
	return { kind = "string", maxLength = maxLength or 64 }
end

function Schema.oneOf(values: { any }): Spec
	return { kind = "oneOf", values = values }
end

-- Vector3 인스턴스 또는 {X,Y,Z} 테이블. NaN/inf 거부. unit=true면 길이를 1±tolerance로 제한.
function Schema.vector3(opts: { unit: boolean?, tolerance: number? }?): Spec
	local o: { unit: boolean?, tolerance: number? } = opts or {}
	return { kind = "vector3", unit = o.unit, tolerance = o.tolerance or 0.1 }
end

function Schema.optional(inner: Spec): Spec
	return { kind = "optional", inner = inner }
end

-- 알 수 없는 필드는 항상 거부한다(strict).
function Schema.object(fields: { [string]: Spec }): Spec
	return { kind = "object", fields = fields }
end

function Schema.array(item: Spec, maxLength: number): Spec
	return { kind = "array", item = item, maxLength = maxLength }
end

local function readXYZ(v: any): (number?, number?, number?)
	if typeof(v) == "Vector3" then
		return v.X, v.Y, v.Z
	end
	if type(v) == "table" then
		local x, y, z = v.X, v.Y, v.Z
		if type(x) == "number" and type(y) == "number" and type(z) == "number" then
			return x, y, z
		end
	end
	return nil, nil, nil
end

local function check(spec: Spec, value: any, path: string): string?
	local kind = spec.kind
	if kind == "optional" then
		if value == nil then
			return nil
		end
		return check(spec.inner, value, path)
	end
	if value == nil then
		return path .. ": 값 없음"
	end

	if kind == "number" then
		if type(value) ~= "number" then
			return path .. ": number 아님"
		end
		if not isFinite(value) then
			return path .. ": NaN/inf"
		end
		if spec.integer and value ~= math.floor(value) then
			return path .. ": 정수 아님"
		end
		if spec.min ~= nil and value < spec.min then
			return path .. ": 최솟값 미만"
		end
		if spec.max ~= nil and value > spec.max then
			return path .. ": 최댓값 초과"
		end
		return nil
	elseif kind == "boolean" then
		return if type(value) == "boolean" then nil else path .. ": boolean 아님"
	elseif kind == "string" then
		if type(value) ~= "string" then
			return path .. ": string 아님"
		end
		if #value > spec.maxLength then
			return path .. ": 문자열 너무 김"
		end
		return nil
	elseif kind == "oneOf" then
		for _, allowed in spec.values do
			if allowed == value then
				return nil
			end
		end
		return path .. ": 허용되지 않은 값"
	elseif kind == "vector3" then
		local x, y, z = readXYZ(value)
		if x == nil or y == nil or z == nil then
			return path .. ": Vector3 아님"
		end
		if not (isFinite(x) and isFinite(y) and isFinite(z)) then
			return path .. ": NaN/inf"
		end
		if spec.unit then
			local mag = math.sqrt(x * x + y * y + z * z)
			if math.abs(mag - 1) > spec.tolerance then
				return path .. ": 단위 벡터 아님"
			end
		end
		return nil
	elseif kind == "array" then
		if type(value) ~= "table" then
			return path .. ": table 아님"
		end
		local n = 0
		for k in value do
			if type(k) ~= "number" then
				return path .. ": 배열 아님"
			end
			n += 1
		end
		if n > spec.maxLength or #value ~= n then
			return path .. ": 배열 길이 오류"
		end
		for i, item in value do
			local err = check(spec.item, item, path .. "[" .. i .. "]")
			if err then
				return err
			end
		end
		return nil
	elseif kind == "object" then
		if type(value) ~= "table" then
			return path .. ": table 아님"
		end
		for k in value do
			if type(k) ~= "string" or spec.fields[k] == nil then
				return path .. ": 알 수 없는 필드 " .. tostring(k)
			end
		end
		for name, fieldSpec in spec.fields do
			local err = check(fieldSpec, value[name], path .. "." .. name)
			if err then
				return err
			end
		end
		return nil
	end
	return path .. ": 알 수 없는 spec " .. tostring(kind)
end

function Schema.validate(spec: Spec, value: any): (boolean, string?)
	local err = check(spec, value, "$")
	if err then
		return false, err
	end
	return true, nil
end

return Schema
