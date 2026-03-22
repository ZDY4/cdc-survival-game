#pragma once

#include <algorithm>
#include <cstddef>
#include <tuple>
#include <vector>

namespace boost {
namespace heap {

template <bool Value>
struct mutable_ {
	static constexpr bool value = Value;
};

template <int Value>
struct arity {
	static constexpr int value = Value;
};

template <typename Comparator>
struct compare {
	using type = Comparator;
};

template <typename T, typename... Options>
class d_ary_heap {
public:
	using value_type = T;
	using handle_type = std::size_t;

	handle_type push(const value_type &p_value) {
		values_.push_back(p_value);
		_resort();
		return 0;
	}

	const value_type &top() const {
		return values_.front();
	}

	void pop() {
		if (!values_.empty()) {
			values_.erase(values_.begin());
		}
	}

	void clear() {
		values_.clear();
	}

	bool empty() const {
		return values_.empty();
	}

	void increase(handle_type) {
		_resort();
	}

private:
	std::vector<value_type> values_;

	using compare_state = typename std::tuple_element<sizeof...(Options) - 1, std::tuple<Options...>>::type;

	void _resort() {
		auto comparator = typename compare_state::type();
		std::sort(values_.begin(), values_.end(), [&](const value_type &lhs, const value_type &rhs) {
			return comparator(lhs, rhs);
		});
	}
};

} // namespace heap
} // namespace boost
