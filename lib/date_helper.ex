defmodule DateHelper do
  import NumberHelper

	def date_string_from_array date_array do
		[[year, month, day], [hour, minute, second]] = date_array
		"#{leading_zero(day)}.#{leading_zero(month)}.#{year} #{leading_zero(hour)}:#{leading_zero(minute)}:#{leading_zero(second)}"
	end
end