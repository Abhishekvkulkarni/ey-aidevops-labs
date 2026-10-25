def paginate(items, page, size):
    """Return one page of items. Pages are 1-based: page 1 is the first `size` items."""
    if page < 1 or size < 1:
        raise ValueError("page and size must be >= 1")
    start = (page - 1) * size
    return items[start:start + size]
