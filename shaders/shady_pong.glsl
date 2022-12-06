// -----------------------------------------------------------------
// Basic Pong Game written in a single GLSL shader.
// 
// Ported from: https://github.com/KyleBanks/shader-pong
// -----------------------------------------------------------------

precision highp float;

// The size of the screen in pixels.
uniform vec2 SIZE;

// The position of the light source in UV space.
uniform vec2 LIGHT;

// The color of the shadow.
uniform vec4 SHADOW;

// The background color.
uniform vec3 BACKGROUND_COLOR;

// The time between frames in seconds.
uniform float DELTA_TIME;

// The speed of the AI.
uniform float AI_SPEED;

// The texture containing the game state.
uniform sampler2D MEMORY;

// The output color of the fragment.
out vec4 fragColor;

// The size of the ball and paddles.
const float BALL_SIZE = 0.015;
const vec2 PADDLE_SIZE = vec2(0.01, 0.08);

// The color of the vignette effect on the edges of the screen.
const vec4 VIGNETTE = vec4(1, 1, 1, 0.9);

// The maximum number of objects that can be drawn:
// Two paddles and the ball.
const int MAX_OBJECTS = 3;
vec4 objects[MAX_OBJECTS];

#pragma region HELPERS
float saturate(float x) { return max(0, min(1, x)); }

vec3 lerp(vec3 a, vec3 b, float w) { return a + w*(b-a); }
#pragma endregion

#pragma region COORDINATES
// Convert a point from UV to Pixel space.
vec2 uvToPixels(vec2 uv) { return vec2(SIZE.x * uv.x, SIZE.y * uv.y); }

// Convert a point from Pixel to UV space.
vec2 pixelsToUV(vec2 pixels) { return vec2(pixels.x / SIZE.x, pixels.y / SIZE.y); }

// Create a UV point that represents a square in its equivalent Pixel space, regardless of resolution.
vec2 squareUV(float len) {
    vec2 size = uvToPixels(len.xx);
    size.x = size.y = min(size.x, size.y);
    return pixelsToUV(size);
}

// Returns true if the UV point is contained within a rect defined in Pixel space.
bool inPixelRect(vec2 center, vec2 extents, vec2 uv) {
    uv = uvToPixels(uv);
    return (abs(center.x - uv.x) < extents.x) && (abs(center.y - uv.y) < extents.y);
}

// Returns true if the UV point is contained within a rect defined in UV space. 
bool inUVRect(vec2 center, vec2 extents, vec2 uv) {
    center = uvToPixels(center);
    extents = uvToPixels(extents);
    return inPixelRect(center, extents, uv);
}
#pragma endregion

#pragma region STORE_GAME_STATE
// The memory block size and spacing are defined in UV space.
#define MEMORY_BLOCK_SIZE 0.015
#define MEMORY_BLOCK_SPACING 0.05
#define MEMORY_BLOCK_POS(slot) \
    slot * MEMORY_BLOCK_SIZE + ((slot + 1) * MEMORY_BLOCK_SPACING)

// The memory blocks locations.
const vec2 GAME_STARTED_BLOCK = MEMORY_BLOCK_POS(vec2(0, 0));
const vec2 BALL_POSITION_X = MEMORY_BLOCK_POS(vec2(0, 1));
const vec2 BALL_POSITION_Y = MEMORY_BLOCK_POS(vec2(0, 2));
const vec2 BALL_VELOCITY_X = MEMORY_BLOCK_POS(vec2(0, 3));
const vec2 BALL_VELOCITY_Y = MEMORY_BLOCK_POS(vec2(0, 4));
const vec2 BALL_REVERSED_X = MEMORY_BLOCK_POS(vec2(0, 5));
const vec2 BALL_REVERSED_Y = MEMORY_BLOCK_POS(vec2(0, 6));
const vec2 PLAYER_1_POSITION_Y = MEMORY_BLOCK_POS(vec2(1, 0));
const vec2 PLAYER_2_POSITION_Y = MEMORY_BLOCK_POS(vec2(1, 1));

// The game state.
bool started;
vec2 ballPosition;
vec2 ballVelocity;
bool ballReversedX;
bool ballReversedY;
vec2 player1Position;
vec2 player2Position;

// Read a float from the memory texture.
float readMemory(vec2 block) { return texture(MEMORY, block).a; }     

// Load the game state from the memory texture.
void loadGameState() {
    started = readMemory(GAME_STARTED_BLOCK) > 0.5;
    ballPosition = vec2(
        readMemory(BALL_POSITION_X),
        readMemory(BALL_POSITION_Y)
    );
    ballVelocity = vec2(
        readMemory(BALL_VELOCITY_X), 
        readMemory(BALL_VELOCITY_Y)
    );
    ballReversedX = readMemory(BALL_REVERSED_X) > 0.5;
    ballReversedY = readMemory(BALL_REVERSED_Y) > 0.5;
    player1Position = vec2(
        0.05,
        readMemory(PLAYER_1_POSITION_Y)
    );
    player2Position = vec2(
        1 - 0.05,
        readMemory(PLAYER_2_POSITION_Y)
    );
}

// Save the game state by returning a float that will be written to the 
// memory texture at the given UV point as an alpha value.
float saveGameState(vec2 uv) {
    vec2 blockSize = squareUV(MEMORY_BLOCK_SIZE); 
    if (inUVRect(GAME_STARTED_BLOCK, blockSize, uv)) {
        return started ? 1 : 0;
    } else if (inUVRect(BALL_POSITION_X, blockSize, uv)) {
        return ballPosition.x;
    } else if (inUVRect(BALL_POSITION_Y, blockSize, uv)) {
        return ballPosition.y;
    } else if (inUVRect(BALL_VELOCITY_X, blockSize, uv)) {
        return ballVelocity.x;
    } else if (inUVRect(BALL_VELOCITY_Y, blockSize, uv)) {
        return ballVelocity.y;
    } else if (inUVRect(BALL_REVERSED_X, blockSize, uv)) {
        return ballReversedX ? 1 : 0;
    } else if (inUVRect(BALL_REVERSED_Y, blockSize, uv)) {
        return ballReversedY ? 1 : 0;
    } else if (inUVRect(PLAYER_1_POSITION_Y, blockSize, uv)) {
        return player1Position.y;
    } else if (inUVRect(PLAYER_2_POSITION_Y, blockSize, uv)) {
        return player2Position.y;
    }
    return 0;
}
#pragma endregion

#pragma region PHYSICS

// Check if two lines intersect. Returns true if they do, and writes the 
// collision point to the collision parameter.
//
// The first line is defined by the points (x1, y1) and (x2, y2). The second
// line is defined by the points (x3, y3) and (x4, y4).
//
// Based on the algorithm described here: 
// http://www.jeffreythompson.org/collision-detection/line-rect.php
bool _lineLine(float x1, float y1, float x2, float y2, float x3, float y3, float x4, float y4, out vec2 collision) {
    // calculate the distance to intersection point
    float uA = ((x4-x3)*(y1-y3) - (y4-y3)*(x1-x3)) / ((y4-y3)*(x2-x1) - (x4-x3)*(y2-y1));
    float uB = ((x2-x1)*(y1-y3) - (y2-y1)*(x1-x3)) / ((y4-y3)*(x2-x1) - (x4-x3)*(y2-y1));

    // if uA and uB are between 0-1, lines are colliding
    bool hit = uA >= 0 && uA <= 1 && uB >= 0 && uB <= 1;
    if (hit) {
        collision = vec2(x1 + (uA * (x2-x1)), y1 + (uA * (y2-y1)));
    }
    return hit;
}

// Check if the line intersects the rectangle. Returns true if they do, and
// writes the collision point to the collision parameter.
//
// The line is defined by the points (x1, y1) and (x2, y2). The rectangle is
// defined by the point (rx, ry) and the width and height (rw, rh).
//
// Based on the algorithm described here: 
// http://www.jeffreythompson.org/collision-detection/line-rect.php
bool _lineRect(float x1, float y1, float x2, float y2, float rx, float ry, float rw, float rh, out vec2 collision) {
    bool left = _lineLine(x1, y1, x2, y2, rx - rw, ry - rh, rx - rw, ry + rh, collision);
    if (left) {
        return true;
    }
    bool right = _lineLine(x1, y1, x2, y2, rx + rw, ry - rh, rx + rw, ry + rh, collision);
    if (right) {
        return true;
    }
    bool top = _lineLine(x1, y1, x2, y2, rx - rw, ry + rh, rx + rw, ry + rh, collision);
    if (top) {
        return true;
    }
    bool bottom = _lineLine(x1, y1, x2, y2, rx - rw, ry - rh, rx + rw, ry - rh, collision);
    if (bottom) {
        return true;
    }
    return false;
}

// Check if the array of objects contains a collision with the line represented by the 
// start and end arguments
//
// Stores the collision point in the collision argument.
bool lineCollides(vec4[3] objects, vec2 start, vec2 end, out vec2 collision) {
    start = uvToPixels(start);
    end = uvToPixels(end);

    for (int i = 0; i < objects.length(); i++) {
        vec4 object = objects[i];
        if (_lineRect(start.x, start.y, end.x, end.y, object.x, object.y, object.z, object.w, collision)) {
            collision = pixelsToUV(collision);
            return true;
        }
    }
    return false;
} 

// Check if the array of objects contains a collision with the line represented by the 
// start and end arguments
//
// Stores the collision point in the collision argument.
bool lineCollides(vec4[2] objects, vec2 start, vec2 end, out vec2 collision) {
    start = uvToPixels(start);
    end = uvToPixels(end);

    for (int i = 0; i < objects.length(); i++) {
        vec4 object = objects[i];
        if (_lineRect(start.x, start.y, end.x, end.y, object.x, object.y, object.z, object.w, collision)) {
            collision = pixelsToUV(collision);
            return true;
        }
    }
    return false;
}  
#pragma endregion

#pragma region GAME_LOOP
// Draw the background using the VIGNETTE and BACKGROUND_COLOR constants.
void drawBackground(inout vec3 result, vec2 uv) {
    float t = distance(uv, vec2(0.5)) / VIGNETTE.a;
    result = lerp(VIGNETTE.rgb, BACKGROUND_COLOR, t);
}

// Draw the shadows of the objects relative to the light source.
void drawShadows(inout vec3 result, vec2 uv) {
    vec2 _;
    bool shadow = lineCollides(objects, uv, LIGHT, _);
    result = lerp(result, SHADOW.rgb, (shadow ? 1 : 0) * SHADOW.a);
}

// Draw the objects.
void drawObjects(inout vec3 result, vec2 uv) {
    for (int i = 0; i < MAX_OBJECTS; i++) {
        if (inPixelRect(objects[i].xy, objects[i].zw, uv)) {
            result = 1 - BACKGROUND_COLOR;
        }
    }
}

// Reset the ball to the center of the screen.
void resetBall() {
    ballPosition = vec2(0.5, 0.5);
    ballVelocity = vec2(0.5, 0.89); // TODO: random?
}

// Start the game and initialize the game state.
void startGame() {
    if (started) {
        return;
    }
    
    started = true;

    player1Position.y = 0.5;
    player2Position.y = 0.5;

    resetBall();
}

// Render the game.
vec3 renderGame(vec2 uv) {
    vec3 result;
    drawBackground(result, uv);
    drawShadows(result, uv);
    drawObjects(result, uv);
    return result;
}

// Update the AI player to follow the ball when the ball is in the AI's half of the screen.
void updateAI(inout vec2 pos, float deltaTime) {
    vec2 ballEndPosition = vec2(
        ballPosition.x + (ballVelocity.x * (ballReversedX ? 1 : -1) * 10),
        ballPosition.y + (ballVelocity.y * (ballReversedY ? 1 : -1) * 10)
    );
    vec2 targetPos;
    if (!_lineLine(pos.x, -100, pos.x, 100, ballPosition.x, ballPosition.y, ballEndPosition.x, ballEndPosition.y, targetPos)) {
        return;
    }

    float targetDir = sign(targetPos.y - pos.y);
    float targetDist = abs(targetPos.y - pos.y);
    float movement = targetDir * min(targetDist, AI_SPEED * deltaTime);
    pos.y = saturate(pos.y + movement);
}

// Update the game state.
void updateGame(float deltaTime) {
    vec2 previousBallPosition = vec2(ballPosition.xy);

    // Apply velocity
    ballPosition.x += (ballVelocity.x * (ballReversedX ? 1 : -1)) * deltaTime * 0.5;
    ballPosition.y += (ballVelocity.y * (ballReversedY ? 1 : -1)) * deltaTime * 0.5;

    // Update both players.
    updateAI(player1Position, deltaTime);
    updateAI(player2Position, deltaTime);

    // Create a list of paddles to check for collisions
    vec4[2] paddles;
    paddles[0] = vec4(uvToPixels(player1Position), uvToPixels(PADDLE_SIZE));
    paddles[1] = vec4(uvToPixels(player2Position), uvToPixels(PADDLE_SIZE));

    vec2 paddleCollisionPoint;
    bool collision = lineCollides(paddles, previousBallPosition, ballPosition, paddleCollisionPoint);
    
    // If the ball collided with the paddle, then reverse the velocity
    if (collision) {
        vec2 ballSize = squareUV(BALL_SIZE);
        ballPosition = paddleCollisionPoint - vec2(
            sign(ballVelocity.x * (ballReversedX ? 1 : -1)) * ballSize.x * 1.4, 
            0
        );
        ballReversedX = !ballReversedX;
    }

    // If the ball hit the left or right wall, then reset the ball.
    // 
    // Technically this also means the player scored a point, but I am lazy and don't want to
    // implement rendering logic for that.
    if (ballPosition.x < 0) {
        resetBall();
    } else if (ballPosition.x > 1) {
        resetBall();
    } else if (ballPosition.y < 0 || ballPosition.y > 1) {
         // If the ball hit the top or bottom wall, then reverse the velocity.
        ballPosition.y = saturate(ballPosition.y);
        ballReversedY = !ballReversedY;
    }
}
#pragma endregion

vec4 fragment(vec2 uv) {
    // Load game state from memory (if any) and start the game.
    loadGameState();
    startGame();

    // Update game state.
    updateGame(DELTA_TIME);
    
    // Store game state.
    float memory = saveGameState(uv);

    // Setup objects to render.
    vec2 ballSize = squareUV(BALL_SIZE);
    objects[0] = vec4(uvToPixels(ballPosition), uvToPixels(ballSize));
    objects[1] = vec4(uvToPixels(player1Position), uvToPixels(PADDLE_SIZE));
    objects[2] = vec4(uvToPixels(player2Position), uvToPixels(PADDLE_SIZE));
    
    // Render game.
    vec3 result = renderGame(uv);
    return vec4(result, memory);
}

void main() { fragColor = fragment(gl_FragCoord.xy / SIZE); }
