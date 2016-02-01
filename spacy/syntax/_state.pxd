from libc.string cimport memcpy, memset
from libc.stdlib cimport malloc, calloc, free
from libc.stdint cimport uint32_t
from ..vocab cimport EMPTY_LEXEME
from ..structs cimport TokenC, Entity
from ..lexeme cimport Lexeme
from ..symbols cimport punct
from ..attrs cimport IS_SPACE



cdef cppclass StateC:
    int* _stack
    int* _buffer
    bint* shifted
    TokenC* _sent
    Entity* _ents
    TokenC _empty_token
    int length
    int _s_i
    int _b_i
    int _e_i
    int _break

    __init__(const TokenC* sent, int length) nogil:
        cdef int PADDING = 5
        this._buffer = <int*>calloc(length + (PADDING * 2), sizeof(int))
        this._stack = <int*>calloc(length + (PADDING * 2), sizeof(int))
        this.shifted = <bint*>calloc(length + (PADDING * 2), sizeof(bint))
        this._sent = <TokenC*>calloc(length + (PADDING * 2), sizeof(TokenC))
        this._ents = <Entity*>calloc(length + (PADDING * 2), sizeof(Entity))
        cdef int i
        for i in range(length + (PADDING * 2)):
            this._ents[i].end = -1
            this._sent[i].l_edge = i
            this._sent[i].r_edge = i
        for i in range(length, length + (PADDING * 2)):
            this._sent[i].lex = &EMPTY_LEXEME
        this._sent += PADDING
        this._ents += PADDING
        this._buffer += PADDING
        this._stack += PADDING
        this.shifted += PADDING
        this.length = length
        this._break = -1
        this._s_i = 0
        this._b_i = 0
        this._e_i = 0
        for i in range(length):
            this._buffer[i] = i
        this._empty_token.lex = &EMPTY_LEXEME
        for i in range(length):
            this._sent[i] = sent[i]
            this._buffer[i] = i
        for i in range(length, length + 5):
            this._sent[i].lex = &EMPTY_LEXEME

    __dealloc__():
        free(this._buffer)
        free(this._stack)
        free(this.shifted)
        free(this._sent)
        free(this._ents)

    int S(int i) nogil:
        if i >= this._s_i:
            return -1
        return this._stack[this._s_i - (i+1)]

    int B(int i) nogil:
        if (i + this._b_i) >= this.length:
            return -1
        return this._buffer[this._b_i + i]

    const TokenC* S_(int i) nogil:
        return this.safe_get(this.S(i))

    const TokenC* B_(int i) nogil:
        return this.safe_get(this.B(i))

    const TokenC* H_(int i) nogil:
        return this.safe_get(this.H(i))

    const TokenC* E_(int i) nogil:
        return this.safe_get(this.E(i))

    const TokenC* L_(int i, int idx) nogil:
        return this.safe_get(this.L(i, idx))

    const TokenC* R_(int i, int idx) nogil:
        return this.safe_get(this.R(i, idx))

    const TokenC* safe_get(int i) nogil:
        if i < 0 or i >= this.length:
            return &this._empty_token
        else:
            return &this._sent[i]

    int H(int i) nogil:
        if i < 0 or i >= this.length:
            return -1
        return this._sent[i].head + i

    int E(int i) nogil:
        if this._e_i <= 0 or this._e_i >= this.length:
            return 0
        if i < 0 or i >= this._e_i:
            return 0
        return this._ents[this._e_i - (i+1)].start

    int L(int i, int idx) nogil:
        if idx < 1:
            return -1
        if i < 0 or i >= this.length:
            return -1
        cdef const TokenC* target = &this._sent[i]
        if target.l_kids < idx:
            return -1
        cdef const TokenC* ptr = &this._sent[target.l_edge]

        while ptr < target:
            # If this head is still to the right of us, we can skip to it
            # No token that's between this token and this head could be our
            # child.
            if (ptr.head >= 1) and (ptr + ptr.head) < target:
                ptr += ptr.head

            elif ptr + ptr.head == target:
                idx -= 1
                if idx == 0:
                    return ptr - this._sent
                ptr += 1
            else:
                ptr += 1
        return -1
    
    int R(int i, int idx) nogil:
        if idx < 1:
            return -1
        if i < 0 or i >= this.length:
            return -1
        cdef const TokenC* target = &this._sent[i]
        if target.r_kids < idx:
            return -1
        cdef const TokenC* ptr = &this._sent[target.r_edge]
        while ptr > target:
            # If this head is still to the right of us, we can skip to it
            # No token that's between this token and this head could be our
            # child.
            if (ptr.head < 0) and ((ptr + ptr.head) > target):
                ptr += ptr.head
            elif ptr + ptr.head == target:
                idx -= 1
                if idx == 0:
                    return ptr - this._sent
                ptr -= 1
            else:
                ptr -= 1
        return -1

    bint empty() nogil:
        return this._s_i <= 0

    bint eol() nogil:
        return this.buffer_length() == 0

    bint at_break() nogil:
        return this._break != -1

    bint is_final() nogil:
        return this.stack_depth() <= 0 and this._b_i >= this.length

    bint has_head(int i) nogil:
        return this.safe_get(i).head != 0

    int n_L(int i) nogil:
        return this.safe_get(i).l_kids

    int n_R(int i) nogil:
        return this.safe_get(i).r_kids

    bint stack_is_connected() nogil:
        return False

    bint entity_is_open() nogil:
        if this._e_i < 1:
            return False
        return this._ents[this._e_i-1].end == -1

    int stack_depth() nogil:
        return this._s_i

    int buffer_length() nogil:
        if this._break != -1:
            return this._break - this._b_i
        else:
            return this.length - this._b_i

    void push() nogil:
        if this.B(0) != -1:
            this._stack[this._s_i] = this.B(0)
        this._s_i += 1
        this._b_i += 1
        if this._b_i > this._break:
            this._break = -1

    void pop() nogil:
        if this._s_i >= 1:
            this._s_i -= 1
    
    void unshift() nogil:
        this._b_i -= 1
        this._buffer[this._b_i] = this.S(0)
        this._s_i -= 1
        this.shifted[this.B(0)] = True

    void add_arc(int head, int child, int label) nogil:
        if this.has_head(child):
            this.del_arc(this.H(child), child)

        cdef int dist = head - child
        this._sent[child].head = dist
        this._sent[child].dep = label
        cdef int i
        if child > head:
            this._sent[head].r_kids += 1
            # Some transition systems can have a word in the buffer have a
            # rightward child, e.g. from Unshift.
            this._sent[head].r_edge = this._sent[child].r_edge
            i = 0
            while this.has_head(head) and i < this.length:
                head = this.H(head)
                this._sent[head].r_edge = this._sent[child].r_edge
                i += 1 # Guard against infinite loops
        else:
            this._sent[head].l_kids += 1
            this._sent[head].l_edge = this._sent[child].l_edge

    void del_arc(int h_i, int c_i) nogil:
        cdef int dist = h_i - c_i
        cdef TokenC* h = &this._sent[h_i]
        if c_i > h_i:
            h.r_edge = this.R_(h_i, 2).r_edge if h.r_kids >= 2 else h_i
            h.r_kids -= 1
        else:
            h.l_edge = this.L_(h_i, 2).l_edge if h.l_kids >= 2 else h_i
            h.l_kids -= 1

    void open_ent(int label) nogil:
        this._ents[this._e_i].start = this.B(0)
        this._ents[this._e_i].label = label
        this._ents[this._e_i].end = -1
        this._e_i += 1

    void close_ent() nogil:
        # Note that we don't decrement _e_i here! We want to maintain all
        # entities, not over-write them...
        this._ents[this._e_i-1].end = this.B(0)+1
        this._sent[this.B(0)].ent_iob = 1

    void set_ent_tag(int i, int ent_iob, int ent_type) nogil:
        if 0 <= i < this.length:
            this._sent[i].ent_iob = ent_iob
            this._sent[i].ent_type = ent_type

    void set_break(int i) nogil:
        if 0 <= this.B(0) < this.length: 
            this._sent[this.B(0)].sent_start = True
            this._break = this._b_i

    void clone(const StateC* src) nogil:
        memcpy(this._sent, src._sent, this.length * sizeof(TokenC))
        memcpy(this._stack, src._stack, this.length * sizeof(int))
        memcpy(this._buffer, src._buffer, this.length * sizeof(int))
        memcpy(this._ents, src._ents, this.length * sizeof(Entity))
        this._b_i = src._b_i
        this._s_i = src._s_i
        this._e_i = src._e_i
        this._break = src._break

    void fast_forward() nogil:
        while this.buffer_length() == 0 \
        or this.stack_depth() == 0 \
        or Lexeme.c_check_flag(this.S_(0).lex, IS_SPACE):
            if this.buffer_length() == 1 and this.stack_depth() == 0:
                this.push()
                this.pop()
            elif this.buffer_length() == 0 and this.stack_depth() == 1:
                this.pop()
            elif this.buffer_length() == 0 and this.stack_depth() >= 2:
                if this.has_head(this.S(0)):
                    this.pop()
                else:
                    this.unshift()
            elif (this.length - this._b_i) >= 1 and this.stack_depth() == 0:
                this.push()
            elif Lexeme.c_check_flag(this.S_(0).lex, IS_SPACE):
                this.add_arc(this.B(0), this.S(0), 0)
                this.pop()
            else:
                break
