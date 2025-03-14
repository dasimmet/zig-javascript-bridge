class functions {
    constructor(gl) {
        this.gl = gl;
        this.textures = new Map();
        this.frame_buffer = gl.createFramebuffer();
        this.indexBuffer = gl.createBuffer();
        this.vertexBuffer = gl.createBuffer();
        this.using_fb = 0;
        this.next_texture_id = 1;
    }
    textureCreate(pixelData, width, height, interp) {
        const gl = this.gl;

        const texture = gl.createTexture();
        const id = this.next_texture_id;
        this.next_texture_id += 1;
        this.textures.set(id, [texture, width, height]);

        gl.bindTexture(gl.TEXTURE_2D, texture);

        gl.texImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RGBA,
            width,
            height,
            0,
            gl.RGBA,
            gl.UNSIGNED_BYTE,
            pixelData,
        );

        gl.generateMipmap(gl.TEXTURE_2D);

        if (interp == 0) {
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        } else {
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        }
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

        gl.bindTexture(gl.TEXTURE_2D, null);

        return id;
    }
    textureCreateTarget(width, height, interp) {
        const gl = this.gl;
        const texture = gl.createTexture();
        const id = this.next_texture_id;
        this.next_texture_id += 1;
        this.textures.set(id, [texture, width, height]);

        gl.bindTexture(gl.TEXTURE_2D, texture);

        gl.texImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RGBA,
            width,
            height,
            0,
            gl.RGBA,
            gl.UNSIGNED_BYTE,
            null,
        );

        if (interp == 0) {
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        } else {
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        }
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

        gl.bindTexture(gl.TEXTURE_2D, null);

        return id;
    }
    textureDestroy(id) {
        const texture = this.textures.get(id)[0];
        this.textures.delete(id);
        this.gl.deleteTexture(texture);
    }
    renderTarget(id) {
        const gl = this.gl;
        if (id === 0) {
            this.using_fb = false;
            gl.bindFramebuffer(gl.FRAMEBUFFER, null);
            const renderTargetSize = [gl.drawingBufferWidth, gl.drawingBufferHeight];
            gl.viewport(0, 0, renderTargetSize[0], renderTargetSize[1]);
            gl.scissor(0, 0, renderTargetSize[0], renderTargetSize[1]);
        } else {
            this.using_fb = true;
            gl.bindFramebuffer(gl.FRAMEBUFFER, this.frame_buffer);

            const texture = this.textures.get(id);
            gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture[0], 0);
            const renderTargetSize = [texture[1], texture[2]];
            gl.viewport(0, 0, renderTargetSize[0], renderTargetSize[1]);
            gl.scissor(0, 0, renderTargetSize[0], renderTargetSize[1]);
        }
    }
    textureRead(textureId, pixels_out, width, height) {
        const gl = this.gl;
        const texture = this.textures.get(textureId)[0];

        gl.bindFramebuffer(gl.FRAMEBUFFER, this.frame_buffer);
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);

        gl.readPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, pixels_out, 0);

        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    }
    renderGeometry(textureId, indices, vertices, sizeof_vertex, offset_pos, offset_col, offset_uv, clip, x, y, w, h) {
        //console.log("drawClippedTriangles " + textureId + " sizeof " + sizeof_vertex + " pos " + offset_pos + " col " + offset_col + " uv " + offset_uv);
        const gl = this.gl;
	    const renderTargetSize = [gl.drawingBufferWidth, gl.drawingBufferHeight];

        //let old_scissor;
        if (clip === 1) {
            // just calling getParameter here is quite slow (5-10 ms per frame according to chrome)
            //old_scissor = gl.getParameter(gl.SCISSOR_BOX);
            gl.scissor(x, y, w, h);
        }

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.indexBuffer);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);

        gl.bindBuffer(gl.ARRAY_BUFFER, this.vertexBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);

        let matrix = new Float32Array(16);
        matrix[0] = 2.0 / renderTargetSize[0];
        matrix[1] = 0.0;
        matrix[2] = 0.0;
        matrix[3] = 0.0;
        matrix[4] = 0.0;
        if (this.using_fb) {
            matrix[5] = 2.0 / renderTargetSize[1];
        } else {
            matrix[5] = -2.0 / renderTargetSize[1];
        }
        matrix[6] = 0.0;
        matrix[7] = 0.0;
        matrix[8] = 0.0;
        matrix[9] = 0.0;
        matrix[10] = 1.0;
        matrix[11] = 0.0;
        matrix[12] = -1.0;
        if (this.using_fb) {
            matrix[13] = -1.0;
        } else {
            matrix[13] = 1.0;
        }
        matrix[14] = 0.0;
        matrix[15] = 1.0;

        // vertex
        gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer);
        gl.vertexAttribPointer(
            programInfo.attribLocations.vertexPosition,
            2,  // num components
            gl.FLOAT,
            false,  // don't normalize
            sizeof_vertex,  // stride
            offset_pos,  // offset
        );
        gl.enableVertexAttribArray(programInfo.attribLocations.vertexPosition);

        // color
        gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer);
        gl.vertexAttribPointer(
            programInfo.attribLocations.vertexColor,
            4,  // num components
            gl.UNSIGNED_BYTE,
            false,  // don't normalize
            sizeof_vertex, // stride
            offset_col,  // offset
        );
        gl.enableVertexAttribArray(programInfo.attribLocations.vertexColor);

        // texture
        gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer);
        gl.vertexAttribPointer(
            programInfo.attribLocations.textureCoord,
            2,  // num components
            gl.FLOAT,
            false,  // don't normalize
            sizeof_vertex, // stride
            offset_uv,  // offset
        );
        gl.enableVertexAttribArray(programInfo.attribLocations.textureCoord);

        // Tell WebGL to use our program when drawing
        gl.useProgram(shaderProgram);

        // Set the shader uniforms
        gl.uniformMatrix4fv(
            programInfo.uniformLocations.matrix,
            false,
            matrix,
        );

        if (textureId != 0) {
            gl.activeTexture(gl.TEXTURE0);
            gl.bindTexture(gl.TEXTURE_2D, textures.get(textureId)[0]);
            gl.uniform1i(programInfo.uniformLocations.useTex, 1);
        } else {
            gl.bindTexture(gl.TEXTURE_2D, null);
            gl.uniform1i(programInfo.uniformLocations.useTex, 0);
        }

        gl.uniform1i(programInfo.uniformLocations.uSampler, 0);

        //console.log("drawElements " + textureId);
        gl.drawElements(gl.TRIANGLES, indices.length, gl.UNSIGNED_SHORT, 0);

        if (clip === 1) {
            //gl.scissor(old_scissor[0], old_scissor[1], old_scissor[2], old_scissor[3]);
            gl.scissor(0, 0, renderTargetSize[0], renderTargetSize[1]);
        }
    }
}
