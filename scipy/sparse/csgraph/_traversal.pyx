"""
Routines for traversing graphs in compressed sparse format
"""

# Author: Jake Vanderplas  -- <vanderplas@astro.washington.edu>
# License: BSD, (C) 2012

import numpy as np
cimport numpy as np

from scipy.sparse import csr_matrix, isspmatrix, isspmatrix_csr, isspmatrix_csc
from scipy.sparse.csgraph._validation import validate_graph
from scipy.sparse.csgraph._tools import reconstruct_path

cimport cython
from libc cimport stdlib

include 'parameters.pxi'

def connected_components(csgraph, directed=True, connection='weak',
                         return_labels=True):
    """
    connected_components(csgraph, directed=True, connection='weak',
                         return_labels=True)

    Analyze the connected components of a sparse graph

    .. versionadded:: 0.11.0

    Parameters
    ----------
    csgraph : array_like or sparse matrix
        The N x N matrix representing the compressed sparse graph.  The input
        csgraph will be converted to csr format for the calculation.
    directed : bool, optional
        If True (default), then operate on a directed graph: only
        move from point i to point j along paths csgraph[i, j].
        If False, then find the shortest path on an undirected graph: the
        algorithm can progress from point i to j along csgraph[i, j] or
        csgraph[j, i].
    connection : str, optional
        ['weak'|'strong'].  For directed graphs, the type of connection to
        use.  Nodes i and j are strongly connected if a path exists both
        from i to j and from j to i. A directed graph is weakly connected
        if replacing all of its directed edges with undirected edges produces
        a connected (undirected) graph. If directed == False, this keyword
        is not referenced.
    return_labels : bool, optional
        If True (default), then return the labels for each of the connected
        components.

    Returns
    -------
    n_components: int
        The number of connected components.
    labels: ndarray
        The length-N array of labels of the connected components.

    References
    ----------
    .. [1] D. J. Pearce, "An Improved Algorithm for Finding the Strongly
           Connected Components of a Directed Graph", Technical Report, 2005

    Examples
    --------
    >>> from scipy.sparse import csr_matrix
    >>> from scipy.sparse.csgraph import connected_components

    >>> graph = [
    ... [0, 1, 1, 0, 0],
    ... [0, 0, 1, 0, 0],
    ... [0, 0, 0, 0, 0],
    ... [0, 0, 0, 0, 1],
    ... [0, 0, 0, 0, 0]
    ... ]
    >>> graph = csr_matrix(graph)
    >>> print(graph)
      (0, 1)	1
      (0, 2)	1
      (1, 2)	1
      (3, 4)	1

    >>> n_components, labels = connected_components(csgraph=graph, directed=False, return_labels=True)
    >>> n_components
    2
    >>> labels
    array([0, 0, 0, 1, 1], dtype=int32)

    """
    if connection.lower() not in ['weak', 'strong']:
        raise ValueError("connection must be 'weak' or 'strong'")

    # weak connections <=> components of undirected graph
    if connection.lower() == 'weak':
        directed = False

    csgraph = validate_graph(csgraph, directed,
                             dtype=csgraph.dtype,
                             dense_output=False)

    labels = np.empty(csgraph.shape[0], dtype=ITYPE)
    labels.fill(NULL_IDX)

    if directed:
        n_components = _connected_components_directed(csgraph.indices,
                                                      csgraph.indptr,
                                                      labels)
    else:
        csgraph_T = csgraph.T.tocsr()
        n_components = _connected_components_undirected(csgraph.indices,
                                                        csgraph.indptr,
                                                        csgraph_T.indices,
                                                        csgraph_T.indptr,
                                                        labels)

    if return_labels:
        return n_components, labels
    else:
        return n_components


def breadth_first_tree(csgraph, i_start, directed=True):
    r"""
    breadth_first_tree(csgraph, i_start, directed=True)

    Return the tree generated by a breadth-first search

    Note that a breadth-first tree from a specified node is unique.

    .. versionadded:: 0.11.0

    Parameters
    ----------
    csgraph : array_like or sparse matrix
        The N x N matrix representing the compressed sparse graph.  The input
        csgraph will be converted to csr format for the calculation.
    i_start : int
        The index of starting node.
    directed : bool, optional
        If True (default), then operate on a directed graph: only
        move from point i to point j along paths csgraph[i, j].
        If False, then find the shortest path on an undirected graph: the
        algorithm can progress from point i to j along csgraph[i, j] or
        csgraph[j, i].

    Returns
    -------
    cstree : csr matrix
        The N x N directed compressed-sparse representation of the breadth-
        first tree drawn from csgraph, starting at the specified node.

    Examples
    --------
    The following example shows the computation of a depth-first tree
    over a simple four-component graph, starting at node 0::

         input graph          breadth first tree from (0)

             (0)                         (0)
            /   \                       /   \
           3     8                     3     8
          /       \                   /       \
        (3)---5---(1)               (3)       (1)
          \       /                           /
           6     2                           2
            \   /                           /
             (2)                         (2)

    In compressed sparse representation, the solution looks like this:

    >>> from scipy.sparse import csr_matrix
    >>> from scipy.sparse.csgraph import breadth_first_tree
    >>> X = csr_matrix([[0, 8, 0, 3],
    ...                 [0, 0, 2, 5],
    ...                 [0, 0, 0, 6],
    ...                 [0, 0, 0, 0]])
    >>> Tcsr = breadth_first_tree(X, 0, directed=False)
    >>> Tcsr.toarray().astype(int)
    array([[0, 8, 0, 3],
           [0, 0, 2, 0],
           [0, 0, 0, 0],
           [0, 0, 0, 0]])

    Note that the resulting graph is a Directed Acyclic Graph which spans
    the graph.  A breadth-first tree from a given node is unique.
    """
    node_list, predecessors = breadth_first_order(csgraph, i_start,
                                                  directed, True)
    return reconstruct_path(csgraph, predecessors, directed)


def depth_first_tree(csgraph, i_start, directed=True):
    r"""
    depth_first_tree(csgraph, i_start, directed=True)

    Return a tree generated by a depth-first search.

    Note that a tree generated by a depth-first search is not unique:
    it depends on the order that the children of each node are searched.

    .. versionadded:: 0.11.0

    Parameters
    ----------
    csgraph : array_like or sparse matrix
        The N x N matrix representing the compressed sparse graph.  The input
        csgraph will be converted to csr format for the calculation.
    i_start : int
        The index of starting node.
    directed : bool, optional
        If True (default), then operate on a directed graph: only
        move from point i to point j along paths csgraph[i, j].
        If False, then find the shortest path on an undirected graph: the
        algorithm can progress from point i to j along csgraph[i, j] or
        csgraph[j, i].

    Returns
    -------
    cstree : csr matrix
        The N x N directed compressed-sparse representation of the depth-
        first tree drawn from csgraph, starting at the specified node.

    Examples
    --------
    The following example shows the computation of a depth-first tree
    over a simple four-component graph, starting at node 0::

         input graph           depth first tree from (0)

             (0)                         (0)
            /   \                           \
           3     8                           8
          /       \                           \
        (3)---5---(1)               (3)       (1)
          \       /                   \       /
           6     2                     6     2
            \   /                       \   /
             (2)                         (2)

    In compressed sparse representation, the solution looks like this:

    >>> from scipy.sparse import csr_matrix
    >>> from scipy.sparse.csgraph import depth_first_tree
    >>> X = csr_matrix([[0, 8, 0, 3],
    ...                 [0, 0, 2, 5],
    ...                 [0, 0, 0, 6],
    ...                 [0, 0, 0, 0]])
    >>> Tcsr = depth_first_tree(X, 0, directed=False)
    >>> Tcsr.toarray().astype(int)
    array([[0, 8, 0, 0],
           [0, 0, 2, 0],
           [0, 0, 0, 6],
           [0, 0, 0, 0]])

    Note that the resulting graph is a Directed Acyclic Graph which spans
    the graph.  Unlike a breadth-first tree, a depth-first tree of a given
    graph is not unique if the graph contains cycles.  If the above solution
    had begun with the edge connecting nodes 0 and 3, the result would have
    been different.
    """
    node_list, predecessors = depth_first_order(csgraph, i_start,
                                                directed, True)
    return reconstruct_path(csgraph, predecessors, directed)


cpdef breadth_first_order(csgraph, i_start,
                          directed=True, return_predecessors=True):
    """
    breadth_first_order(csgraph, i_start, directed=True, return_predecessors=True)

    Return a breadth-first ordering starting with specified node.

    Note that a breadth-first order is not unique, but the tree which it
    generates is unique.

    .. versionadded:: 0.11.0

    Parameters
    ----------
    csgraph : array_like or sparse matrix
        The N x N compressed sparse graph.  The input csgraph will be
        converted to csr format for the calculation.
    i_start : int
        The index of starting node.
    directed : bool, optional
        If True (default), then operate on a directed graph: only
        move from point i to point j along paths csgraph[i, j].
        If False, then find the shortest path on an undirected graph: the
        algorithm can progress from point i to j along csgraph[i, j] or
        csgraph[j, i].
    return_predecessors : bool, optional
        If True (default), then return the predecesor array (see below).

    Returns
    -------
    node_array : ndarray, one dimension
        The breadth-first list of nodes, starting with specified node.  The
        length of node_array is the number of nodes reachable from the
        specified node.
    predecessors : ndarray, one dimension
        Returned only if return_predecessors is True.
        The length-N list of predecessors of each node in a breadth-first
        tree.  If node i is in the tree, then its parent is given by
        predecessors[i]. If node i is not in the tree (and for the parent
        node) then predecessors[i] = -9999.

    Examples
    --------
    >>> from scipy.sparse import csr_matrix
    >>> from scipy.sparse.csgraph import breadth_first_order

    >>> graph = [
    ... [0, 1, 2, 0],
    ... [0, 0, 0, 1],
    ... [2, 0, 0, 3],
    ... [0, 0, 0, 0]
    ... ]
    >>> graph = csr_matrix(graph)
    >>> print(graph)
      (0, 1)    1
      (0, 2)    2
      (1, 3)    1
      (2, 0)    2
      (2, 3)    3

    >>> breadth_first_order(graph,0)
    (array([0, 1, 2, 3], dtype=int32), array([-9999,     0,     0,     1], dtype=int32))

    """
    csgraph = validate_graph(csgraph, directed, dense_output=False)
    cdef int N = csgraph.shape[0]

    cdef np.ndarray node_list = np.empty(N, dtype=ITYPE)
    cdef np.ndarray predecessors = np.empty(N, dtype=ITYPE)
    node_list.fill(NULL_IDX)
    predecessors.fill(NULL_IDX)

    if directed:
        length = _breadth_first_directed(i_start,
                                csgraph.indices, csgraph.indptr,
                                node_list, predecessors)
    else:
        csgraph_T = csgraph.T.tocsr()
        length = _breadth_first_undirected(i_start,
                                           csgraph.indices, csgraph.indptr,
                                           csgraph_T.indices, csgraph_T.indptr,
                                           node_list, predecessors)

    if return_predecessors:
        return node_list[:length], predecessors
    else:
        return node_list[:length]


cdef unsigned int _breadth_first_directed(
                           unsigned int head_node,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indices,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indptr,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] node_list,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] predecessors):
    # Inputs:
    #  head_node: (input) index of the node from which traversal starts
    #  indices: (input) CSR indices of graph
    #  indptr:  (input) CSR indptr of graph
    #  node_list: (output) breadth-first list of nodes
    #  predecessors: (output) list of predecessors of nodes in breadth-first
    #                tree.  Should be initialized to NULL_IDX
    # Returns:
    #  n_nodes: the number of nodes in the breadth-first tree
    cdef unsigned int i, pnode, cnode
    cdef unsigned int i_nl, i_nl_end
    cdef unsigned int N = node_list.shape[0]

    node_list[0] = head_node
    i_nl = 0
    i_nl_end = 1

    while i_nl < i_nl_end:
        pnode = node_list[i_nl]

        for i in range(indptr[pnode], indptr[pnode + 1]):
            cnode = indices[i]
            if (cnode == head_node):
                continue
            elif (predecessors[cnode] == NULL_IDX):
                node_list[i_nl_end] = cnode
                predecessors[cnode] = pnode
                i_nl_end += 1

        i_nl += 1

    return i_nl


cdef unsigned int _breadth_first_undirected(
                           unsigned int head_node,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indices1,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indptr1,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indices2,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indptr2,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] node_list,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] predecessors):
    # Inputs:
    #  head_node: (input) index of the node from which traversal starts
    #  indices1: (input) CSR indices of graph
    #  indptr1:  (input) CSR indptr of graph
    #  indices2: (input) CSR indices of transposed graph
    #  indptr2:  (input) CSR indptr of transposed graph
    #  node_list: (output) breadth-first list of nodes
    #  predecessors: (output) list of predecessors of nodes in breadth-first
    #                tree.  Should be initialized to NULL_IDX
    # Returns:
    #  n_nodes: the number of nodes in the breadth-first tree
    cdef unsigned int i, pnode, cnode
    cdef unsigned int i_nl, i_nl_end
    cdef unsigned int N = node_list.shape[0]

    node_list[0] = head_node
    i_nl = 0
    i_nl_end = 1

    while i_nl < i_nl_end:
        pnode = node_list[i_nl]

        for i in range(indptr1[pnode], indptr1[pnode + 1]):
            cnode = indices1[i]
            if (cnode == head_node):
                continue
            elif (predecessors[cnode] == NULL_IDX):
                node_list[i_nl_end] = cnode
                predecessors[cnode] = pnode
                i_nl_end += 1

        for i in range(indptr2[pnode], indptr2[pnode + 1]):
            cnode = indices2[i]
            if (cnode == head_node):
                continue
            elif (predecessors[cnode] == NULL_IDX):
                node_list[i_nl_end] = cnode
                predecessors[cnode] = pnode
                i_nl_end += 1

        i_nl += 1

    return i_nl


cpdef depth_first_order(csgraph, i_start,
                        directed=True, return_predecessors=True):
    """
    depth_first_order(csgraph, i_start, directed=True, return_predecessors=True)

    Return a depth-first ordering starting with specified node.

    Note that a depth-first order is not unique.  Furthermore, for graphs
    with cycles, the tree generated by a depth-first search is not
    unique either.

    .. versionadded:: 0.11.0

    Parameters
    ----------
    csgraph : array_like or sparse matrix
        The N x N compressed sparse graph.  The input csgraph will be
        converted to csr format for the calculation.
    i_start : int
        The index of starting node.
    directed : bool, optional
        If True (default), then operate on a directed graph: only
        move from point i to point j along paths csgraph[i, j].
        If False, then find the shortest path on an undirected graph: the
        algorithm can progress from point i to j along csgraph[i, j] or
        csgraph[j, i].
    return_predecessors : bool, optional
        If True (default), then return the predecesor array (see below).

    Returns
    -------
    node_array : ndarray, one dimension
        The depth-first list of nodes, starting with specified node.  The
        length of node_array is the number of nodes reachable from the
        specified node.
    predecessors : ndarray, one dimension
        Returned only if return_predecessors is True.
        The length-N list of predecessors of each node in a depth-first
        tree.  If node i is in the tree, then its parent is given by
        predecessors[i]. If node i is not in the tree (and for the parent
        node) then predecessors[i] = -9999.

    Examples
    --------
    >>> from scipy.sparse import csr_matrix
    >>> from scipy.sparse.csgraph import depth_first_order

    >>> graph = [
    ... [0, 1, 2, 0],
    ... [0, 0, 0, 1],
    ... [2, 0, 0, 3],
    ... [0, 0, 0, 0]
    ... ]
    >>> graph = csr_matrix(graph)
    >>> print(graph)
      (0, 1)	1
      (0, 2)	2
      (1, 3)	1
      (2, 0)	2
      (2, 3)	3

    >>> depth_first_order(graph,0)
    (array([0, 1, 3, 2], dtype=int32), array([-9999,     0,     0,     1], dtype=int32))

    """
    csgraph = validate_graph(csgraph, directed, dense_output=False)
    cdef int N = csgraph.shape[0]

    node_list = np.empty(N, dtype=ITYPE)
    predecessors = np.empty(N, dtype=ITYPE)
    root_list = np.empty(N, dtype=ITYPE)
    flag = np.zeros(N, dtype=ITYPE)
    node_list.fill(NULL_IDX)
    predecessors.fill(NULL_IDX)
    root_list.fill(NULL_IDX)

    if directed:
        length = _depth_first_directed(i_start,
                              csgraph.indices, csgraph.indptr,
                              node_list, predecessors,
                              root_list, flag)
    else:
        csgraph_T = csgraph.T.tocsr()
        length = _depth_first_undirected(i_start,
                                         csgraph.indices, csgraph.indptr,
                                         csgraph_T.indices, csgraph_T.indptr,
                                         node_list, predecessors,
                                         root_list, flag)

    if return_predecessors:
        return node_list[:length], predecessors
    else:
        return node_list[:length]


cdef unsigned int _depth_first_directed(
                           unsigned int head_node,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indices,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indptr,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] node_list,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] predecessors,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] root_list,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] flag):
    cdef unsigned int i, j, i_nl_end, cnode, pnode
    cdef unsigned int N = node_list.shape[0]
    cdef int no_children, i_root

    node_list[0] = head_node
    root_list[0] = head_node
    i_root = 0
    i_nl_end = 1
    flag[head_node] = 1

    while i_root >= 0:
        pnode = root_list[i_root]
        no_children = True
        for i in range(indptr[pnode], indptr[pnode + 1]):
            cnode = indices[i]
            if flag[cnode]:
                continue
            else:
                i_root += 1
                root_list[i_root] = cnode
                node_list[i_nl_end] = cnode
                predecessors[cnode] = pnode
                flag[cnode] = 1
                i_nl_end += 1
                no_children = False
                break

        if i_nl_end == N:
            break

        if no_children:
            i_root -= 1

    return i_nl_end


cdef unsigned int _depth_first_undirected(
                           unsigned int head_node,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indices1,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indptr1,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indices2,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indptr2,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] node_list,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] predecessors,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] root_list,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] flag):
    cdef unsigned int i, j, i_nl_end, cnode, pnode
    cdef unsigned int N = node_list.shape[0]
    cdef int no_children, i_root

    node_list[0] = head_node
    root_list[0] = head_node
    i_root = 0
    i_nl_end = 1
    flag[head_node] = 1

    while i_root >= 0:
        pnode = root_list[i_root]
        no_children = True

        for i in range(indptr1[pnode], indptr1[pnode + 1]):
            cnode = indices1[i]
            if flag[cnode]:
                continue
            else:
                i_root += 1
                root_list[i_root] = cnode
                node_list[i_nl_end] = cnode
                predecessors[cnode] = pnode
                flag[cnode] = 1
                i_nl_end += 1
                no_children = False
                break

        if no_children:
            for i in range(indptr2[pnode], indptr2[pnode + 1]):
                cnode = indices2[i]
                if flag[cnode]:
                    continue
                else:
                    i_root += 1
                    root_list[i_root] = cnode
                    node_list[i_nl_end] = cnode
                    predecessors[cnode] = pnode
                    flag[cnode] = 1
                    i_nl_end += 1
                    no_children = False
                    break

        if i_nl_end == N:
            break

        if no_children:
            i_root -= 1

    return i_nl_end


cdef int _connected_components_directed(
                                 np.ndarray[ITYPE_t, ndim=1, mode='c'] indices,
                                 np.ndarray[ITYPE_t, ndim=1, mode='c'] indptr,
                                 np.ndarray[ITYPE_t, ndim=1, mode='c'] labels):
    """
    Uses an iterative version of Tarjan's algorithm to find the
    strongly connected components of a directed graph represented as a
    sparse matrix (scipy.sparse.csc_matrix or scipy.sparse.csr_matrix).

    The algorithmic complexity is for a graph with E edges and V
    vertices is O(E + V).
    The storage requirement is 2*V integer arrays.

    Uses an iterative version of the algorithm described here:
    http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.102.1707

    For more details of the memory optimisations used see here:
    http://www.timl.id.au/SCC
    """
    cdef int v, w, index, low_v, low_w, label, j
    cdef int SS_head, root, stack_head, f, b
    DEF VOID = -1
    DEF END = -2
    cdef int N = labels.shape[0]
    cdef np.ndarray[ITYPE_t, ndim=1, mode="c"] SS, lowlinks, stack_f, stack_b

    lowlinks = labels
    SS = np.ndarray((N,), dtype=ITYPE)
    stack_b = np.ndarray((N,), dtype=ITYPE)
    stack_f = SS

    # The stack of nodes which have been backtracked and are in the current SCC
    SS.fill(VOID)
    SS_head = END

    # The array containing the lowlinks of nodes not yet assigned an SCC. Shares
    # memory with the labels array, since they are not used at the same time.
    lowlinks.fill(VOID)

    # The DFS stack. Stored with both forwards and backwards pointers to allow
    # us to move a node up to the top of the stack, as we only need to visit
    # each node once. stack_f shares memory with SS, as nodes aren't put on the
    # SS stack until after they've been popped from the DFS stack.
    stack_head = END
    stack_f.fill(VOID)
    stack_b.fill(VOID)

    index = 0
    # Count SCC labels backwards so as not to class with lowlinks values.
    label = N - 1
    for v in range(N):
        if lowlinks[v] == VOID:
            # DFS-stack push
            stack_head = v
            stack_f[v] = END
            stack_b[v] = END
            while stack_head != END:
                v = stack_head
                if lowlinks[v] == VOID:
                    lowlinks[v] = index
                    index += 1

                    # Add successor nodes
                    for j in range(indptr[v], indptr[v+1]):
                        w = indices[j]
                        if lowlinks[w] == VOID:
                            with cython.boundscheck(False):
                                # DFS-stack push
                                if stack_f[w] != VOID:
                                    # w is already inside the stack,
                                    # so excise it.
                                    f = stack_f[w]
                                    b = stack_b[w]
                                    if b != END:
                                        stack_f[b] = f
                                    if f != END:
                                        stack_b[f] = b

                                stack_f[w] = stack_head
                                stack_b[w] = END
                                stack_b[stack_head] = w
                                stack_head = w

                else:
                    # DFS-stack pop
                    stack_head = stack_f[v]
                    if stack_head >= 0:
                        stack_b[stack_head] = END
                    stack_f[v] = VOID
                    stack_b[v] = VOID

                    root = 1 # True
                    low_v = lowlinks[v]
                    for j in range(indptr[v], indptr[v+1]):
                        low_w = lowlinks[indices[j]]
                        if low_w < low_v:
                            low_v = low_w
                            root = 0 # False
                    lowlinks[v] = low_v

                    if root: # Found a root node
                        index -= 1
                        # while S not empty and rindex[v] <= rindex[top[S]
                        while SS_head != END and lowlinks[v] <= lowlinks[SS_head]:
                            w = SS_head        # w = pop(S)
                            SS_head = SS[w]
                            SS[w] = VOID

                            labels[w] = label  # rindex[w] = c
                            index -= 1         # index = index - 1
                        labels[v] = label  # rindex[v] = c
                        label -= 1         # c = c - 1
                    else:
                        SS[v] = SS_head  # push(S, v)
                        SS_head = v

    # labels count down from N-1 to zero. Modify them so they
    # count upward from 0
    labels *= -1
    labels += (N - 1)
    return (N - 1) - label

cdef int _connected_components_undirected(
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indices1,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indptr1,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indices2,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indptr2,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] labels):

    cdef int v, w, j, label, SS_head
    cdef int N = labels.shape[0]
    DEF VOID = -1
    DEF END = -2
    labels.fill(VOID)
    label = 0

    # Share memory for the stack and labels, since labels are only
    # applied once a node has been popped from the stack.
    cdef np.ndarray[ITYPE_t, ndim=1, mode="c"] SS = labels
    SS_head = END
    for v in range(N):
        if labels[v] == VOID:
            # SS.push(v)
            SS_head = v
            SS[v] = END

            while SS_head != END:
                # v = SS.pop()
                v = SS_head
                SS_head = SS[v]

                labels[v] = label

                # Push children onto the stack if they haven't been
                # seen at all yet.
                for j in range(indptr1[v], indptr1[v+1]):
                    w = indices1[j]
                    if SS[w] == VOID:
                        SS[w] = SS_head
                        SS_head = w
                for j in range(indptr2[v], indptr2[v+1]):
                    w = indices2[j]
                    if SS[w] == VOID:
                        SS[w] = SS_head
                        SS_head = w
            label += 1

    return label
