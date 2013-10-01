defmodule NumberHelper do
	def leading_zero(number) when number < 10 do
		"0#{number}"
	end

	def leading_zero(number) do
		"#{number}"
	end
end