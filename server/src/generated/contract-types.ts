// GENERATED FILE. Run npm run generate:contracts; do not edit.
export interface paths {
    readonly "/admin/v1/apps": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path?: never;
            readonly cookie?: never;
        };
        readonly get: operations["listApplications"];
        readonly put?: never;
        readonly post: operations["createApplication"];
        readonly delete?: never;
        readonly options?: never;
        readonly head?: never;
        readonly patch?: never;
        readonly trace?: never;
    };
    readonly "/admin/v1/apps/{appId}": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly appId: components["parameters"]["AppId"];
            };
            readonly cookie?: never;
        };
        readonly get: operations["getApplication"];
        readonly put?: never;
        readonly post?: never;
        readonly delete?: never;
        readonly options?: never;
        readonly head?: never;
        readonly patch: operations["updateApplication"];
        readonly trace?: never;
    };
    readonly "/health/live": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path?: never;
            readonly cookie?: never;
        };
        readonly get: operations["getLiveness"];
        readonly put?: never;
        readonly post?: never;
        readonly delete?: never;
        readonly options?: never;
        readonly head?: never;
        readonly patch?: never;
        readonly trace?: never;
    };
    readonly "/health/ready": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path?: never;
            readonly cookie?: never;
        };
        readonly get: operations["getReadiness"];
        readonly put?: never;
        readonly post?: never;
        readonly delete?: never;
        readonly options?: never;
        readonly head?: never;
        readonly patch?: never;
        readonly trace?: never;
    };
    readonly "/metrics": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path?: never;
            readonly cookie?: never;
        };
        readonly get: operations["getMetrics"];
        readonly put?: never;
        readonly post?: never;
        readonly delete?: never;
        readonly options?: never;
        readonly head?: never;
        readonly patch?: never;
        readonly trace?: never;
    };
    readonly "/v1/join-requests": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path?: never;
            readonly cookie?: never;
        };
        /** @description Returns all statuses ordered newest first. */
        readonly get: operations["listMyJoinRequests"];
        readonly put?: never;
        readonly post?: never;
        readonly delete?: never;
        readonly options?: never;
        readonly head?: never;
        readonly patch?: never;
        readonly trace?: never;
    };
    readonly "/v1/rooms": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path?: never;
            readonly cookie?: never;
        };
        readonly get: operations["listRooms"];
        readonly put?: never;
        readonly post: operations["createRoom"];
        readonly delete?: never;
        readonly options?: never;
        readonly head?: never;
        readonly patch?: never;
        readonly trace?: never;
    };
    readonly "/v1/rooms/{roomId}": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly get: operations["getRoom"];
        readonly put?: never;
        readonly post?: never;
        readonly delete: operations["deleteRoom"];
        readonly options?: never;
        readonly head?: never;
        readonly patch?: never;
        readonly trace?: never;
    };
    readonly "/v1/rooms/{roomId}/active-sessions": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        /** @description Returns running and paused sessions ordered by updatedAt descending, then id descending. */
        readonly get: operations["listActiveSessions"];
        readonly put?: never;
        readonly post?: never;
        readonly delete?: never;
        readonly options?: never;
        readonly head?: never;
        readonly patch?: never;
        readonly trace?: never;
    };
    readonly "/v1/rooms/{roomId}/join-requests": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly get: operations["listRoomJoinRequests"];
        readonly put?: never;
        readonly post: operations["requestRoomAccess"];
        readonly delete: operations["cancelRoomAccessRequest"];
        readonly options?: never;
        readonly head?: never;
        readonly patch?: never;
        readonly trace?: never;
    };
    readonly "/v1/rooms/{roomId}/join-requests/{requestId}": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly requestId: components["parameters"]["RequestId"];
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly get?: never;
        readonly put?: never;
        readonly post?: never;
        readonly delete?: never;
        readonly options?: never;
        readonly head?: never;
        readonly patch: operations["decideJoinRequest"];
        readonly trace?: never;
    };
    readonly "/v1/rooms/{roomId}/members/{userId}": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
                readonly userId: components["parameters"]["UserId"];
            };
            readonly cookie?: never;
        };
        readonly get?: never;
        readonly put?: never;
        readonly post?: never;
        readonly delete: operations["removeRoomMember"];
        readonly options?: never;
        readonly head?: never;
        readonly patch?: never;
        readonly trace?: never;
    };
    readonly "/v1/rooms/{roomId}/members/me": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly get?: never;
        readonly put?: never;
        readonly post?: never;
        readonly delete: operations["leaveRoom"];
        readonly options?: never;
        readonly head?: never;
        readonly patch?: never;
        readonly trace?: never;
    };
    readonly "/v1/rooms/{roomId}/messages": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly get: operations["listMessages"];
        readonly put?: never;
        readonly post: operations["sendMessage"];
        readonly delete?: never;
        readonly options?: never;
        readonly head?: never;
        readonly patch?: never;
        readonly trace?: never;
    };
    readonly "/v1/rooms/{roomId}/owner": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly get?: never;
        readonly put: operations["transferRoomOwnership"];
        readonly post?: never;
        readonly delete?: never;
        readonly options?: never;
        readonly head?: never;
        readonly patch?: never;
        readonly trace?: never;
    };
    readonly "/v1/rooms/{roomId}/sessions": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly get?: never;
        readonly put?: never;
        readonly post: operations["startSession"];
        readonly delete?: never;
        readonly options?: never;
        readonly head?: never;
        readonly patch?: never;
        readonly trace?: never;
    };
    readonly "/v1/sessions/{sessionId}": {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly sessionId: components["parameters"]["SessionId"];
            };
            readonly cookie?: never;
        };
        readonly get?: never;
        readonly put?: never;
        readonly post?: never;
        readonly delete?: never;
        readonly options?: never;
        readonly head?: never;
        readonly patch: operations["updateSession"];
        readonly trace?: never;
    };
}
export type webhooks = Record<string, never>;
export interface components {
    schemas: {
        readonly AppId: string;
        readonly Application: {
            readonly appId: components["schemas"]["AppId"];
            readonly audience: string;
            readonly chatRetentionDays: number | null;
            /** Format: date-time */
            readonly createdAt: string;
            readonly enabled: boolean;
            readonly issuer: string;
            /** Format: uri */
            readonly jwksUri: string;
            readonly sessionRetentionDays: number | null;
            /** Format: date-time */
            readonly updatedAt: string;
        };
        readonly ApplicationPage: {
            readonly items: readonly components["schemas"]["Application"][];
            readonly nextCursor: string | null;
        };
        readonly ChatMessage: {
            /** Format: uuid */
            readonly id: string;
            /** Format: uuid */
            readonly roomId: string;
            readonly senderId: components["schemas"]["UserId"];
            readonly senderName: string;
            /** Format: date-time */
            readonly sentAt: string;
            readonly text: string;
        };
        readonly CreateApplicationRequest: {
            readonly appId: components["schemas"]["AppId"];
            readonly audience: string;
            readonly chatRetentionDays?: number | null;
            /** @default true */
            readonly enabled: boolean;
            readonly issuer: string;
            /** Format: uri */
            readonly jwksUri: string;
            readonly sessionRetentionDays?: number | null;
        };
        readonly CreateRoomRequest: {
            readonly title: string;
        };
        readonly DecideJoinRequestRequest: {
            readonly decision: components["schemas"]["JoinRequestDecision"];
        };
        readonly ErrorResponse: {
            readonly code: string;
            readonly details?: unknown;
            readonly message: string;
            readonly requestId: string;
        };
        readonly JoinRequest: {
            /** Format: date-time */
            readonly createdAt: string;
            readonly displayName: string;
            /** Format: uuid */
            readonly id: string;
            /** Format: uuid */
            readonly roomId: string;
            readonly status: components["schemas"]["JoinRequestStatus"];
            /** Format: date-time */
            readonly updatedAt: string;
            readonly userId: components["schemas"]["UserId"];
        };
        /** @enum {string} */
        readonly JoinRequestDecision: "approved" | "rejected";
        readonly JoinRequestPage: {
            readonly items: readonly components["schemas"]["JoinRequest"][];
            /** Format: uuid */
            readonly nextCursor: string | null;
        };
        /** @enum {string} */
        readonly JoinRequestStatus: "pending" | "approved" | "rejected" | "cancelled";
        readonly LivenessResponse: {
            /** @constant */
            readonly status: "ok";
        };
        readonly Member: {
            readonly avatarUrl: string;
            readonly displayName: string;
            readonly id: components["schemas"]["UserId"];
            readonly role: components["schemas"]["RoomRole"];
            readonly status: components["schemas"]["PresenceStatus"];
        };
        readonly MessagePage: {
            readonly items: readonly components["schemas"]["ChatMessage"][];
            /** Format: uuid */
            readonly nextCursor: string | null;
        };
        readonly MetricsResponse: string;
        /** @enum {string} */
        readonly PresenceStatus: "online" | "focusing" | "idle" | "away" | "offline";
        readonly ReadinessResponse: {
            /** @constant */
            readonly status: "ready";
        };
        readonly Room: {
            readonly appId: components["schemas"]["AppId"];
            /** Format: uuid */
            readonly id: string;
            readonly members: readonly components["schemas"]["Member"][];
            readonly title: string;
            readonly version: number;
        };
        readonly RoomPage: {
            readonly items: readonly components["schemas"]["Room"][];
            /** Format: uuid */
            readonly nextCursor: string | null;
        };
        /** @enum {string} */
        readonly RoomRole: "owner" | "member";
        readonly SendMessageRequest: {
            readonly text: string;
        };
        readonly SessionPage: {
            readonly items: readonly components["schemas"]["StudySession"][];
            /** Format: uuid */
            readonly nextCursor: string | null;
        };
        /** @enum {string} */
        readonly SessionStatus: "running" | "paused" | "finished";
        readonly StudySession: {
            /** Format: date-time */
            readonly finishedAt: string | null;
            /** Format: uuid */
            readonly id: string;
            /** Format: uuid */
            readonly roomId: string;
            /** Format: date-time */
            readonly startedAt: string;
            readonly status: components["schemas"]["SessionStatus"];
            /** Format: date-time */
            readonly updatedAt: string;
            readonly userId: components["schemas"]["UserId"];
        };
        readonly TransferOwnershipRequest: {
            readonly userId: components["schemas"]["UserId"];
        };
        readonly UpdateApplicationRequest: {
            readonly audience?: string;
            readonly chatRetentionDays?: number | null;
            readonly enabled?: boolean;
            readonly issuer?: string;
            /** Format: uri */
            readonly jwksUri?: string;
            readonly sessionRetentionDays?: number | null;
        };
        readonly UpdateSessionRequest: {
            readonly status: components["schemas"]["SessionStatus"];
        };
        readonly UserId: string;
    };
    responses: {
        /** @description Invalid request */
        readonly BadRequest: {
            headers: {
                readonly "x-request-id": components["headers"]["RequestId"];
                readonly [name: string]: unknown;
            };
            content: {
                readonly "application/json": components["schemas"]["ErrorResponse"];
            };
        };
        /** @description Resource state conflict */
        readonly Conflict: {
            headers: {
                readonly "x-request-id": components["headers"]["RequestId"];
                readonly [name: string]: unknown;
            };
            content: {
                readonly "application/json": components["schemas"]["ErrorResponse"];
            };
        };
        /** @description Access denied */
        readonly Forbidden: {
            headers: {
                readonly "x-request-id": components["headers"]["RequestId"];
                readonly [name: string]: unknown;
            };
            content: {
                readonly "application/json": components["schemas"]["ErrorResponse"];
            };
        };
        /** @description Internal server error */
        readonly InternalServerError: {
            headers: {
                readonly "x-request-id": components["headers"]["RequestId"];
                readonly [name: string]: unknown;
            };
            content: {
                readonly "application/json": components["schemas"]["ErrorResponse"];
            };
        };
        /** @description Resource not found */
        readonly NotFound: {
            headers: {
                readonly "x-request-id": components["headers"]["RequestId"];
                readonly [name: string]: unknown;
            };
            content: {
                readonly "application/json": components["schemas"]["ErrorResponse"];
            };
        };
        /** @description A required dependency is unavailable */
        readonly ServiceUnavailable: {
            headers: {
                readonly "x-request-id": components["headers"]["RequestId"];
                readonly [name: string]: unknown;
            };
            content: {
                readonly "application/json": components["schemas"]["ErrorResponse"];
            };
        };
        /** @description Rate limit exceeded */
        readonly TooManyRequests: {
            headers: {
                readonly "Retry-After": components["headers"]["RetryAfter"];
                readonly "x-request-id": components["headers"]["RequestId"];
                readonly [name: string]: unknown;
            };
            content: {
                readonly "application/json": components["schemas"]["ErrorResponse"];
            };
        };
        /** @description Authentication failed */
        readonly Unauthorized: {
            headers: {
                readonly "x-request-id": components["headers"]["RequestId"];
                readonly [name: string]: unknown;
            };
            content: {
                readonly "application/json": components["schemas"]["ErrorResponse"];
            };
        };
    };
    parameters: {
        readonly AppId: components["schemas"]["AppId"];
        readonly Cursor: string;
        readonly Limit: number;
        readonly RequestId: string;
        readonly RoomId: string;
        readonly SessionId: string;
        readonly UserId: components["schemas"]["UserId"];
        readonly UuidCursor: string;
    };
    requestBodies: never;
    headers: {
        /** @description Request correlation identifier */
        readonly RequestId: string;
        /** @description Seconds until the current rate-limit window permits another request */
        readonly RetryAfter: number;
    };
    pathItems: never;
}
export type $defs = Record<string, never>;
export interface operations {
    readonly listApplications: {
        readonly parameters: {
            readonly query?: {
                readonly cursor?: components["parameters"]["Cursor"];
                readonly limit?: components["parameters"]["Limit"];
            };
            readonly header?: never;
            readonly path?: never;
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Applications */
            readonly 200: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["ApplicationPage"];
                };
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly createApplication: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path?: never;
            readonly cookie?: never;
        };
        readonly requestBody: {
            readonly content: {
                readonly "application/json": components["schemas"]["CreateApplicationRequest"];
            };
        };
        readonly responses: {
            /** @description Created application */
            readonly 201: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["Application"];
                };
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 409: components["responses"]["Conflict"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly getApplication: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly appId: components["parameters"]["AppId"];
            };
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Application */
            readonly 200: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["Application"];
                };
            };
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 404: components["responses"]["NotFound"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly updateApplication: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly appId: components["parameters"]["AppId"];
            };
            readonly cookie?: never;
        };
        readonly requestBody: {
            readonly content: {
                readonly "application/json": components["schemas"]["UpdateApplicationRequest"];
            };
        };
        readonly responses: {
            /** @description Updated application */
            readonly 200: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["Application"];
                };
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 404: components["responses"]["NotFound"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly getLiveness: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path?: never;
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Process is alive */
            readonly 200: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["LivenessResponse"];
                };
            };
            readonly 500: components["responses"]["InternalServerError"];
        };
    };
    readonly getReadiness: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path?: never;
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Dependencies are ready */
            readonly 200: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["ReadinessResponse"];
                };
            };
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly getMetrics: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path?: never;
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Prometheus exposition format */
            readonly 200: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "text/plain": components["schemas"]["MetricsResponse"];
                };
            };
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly listMyJoinRequests: {
        readonly parameters: {
            readonly query?: {
                readonly cursor?: components["parameters"]["UuidCursor"];
                readonly limit?: components["parameters"]["Limit"];
            };
            readonly header?: never;
            readonly path?: never;
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Current user's requests */
            readonly 200: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["JoinRequestPage"];
                };
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly listRooms: {
        readonly parameters: {
            readonly query?: {
                readonly cursor?: components["parameters"]["UuidCursor"];
                readonly limit?: components["parameters"]["Limit"];
            };
            readonly header?: never;
            readonly path?: never;
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Joined rooms */
            readonly 200: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["RoomPage"];
                };
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly createRoom: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path?: never;
            readonly cookie?: never;
        };
        readonly requestBody: {
            readonly content: {
                readonly "application/json": components["schemas"]["CreateRoomRequest"];
            };
        };
        readonly responses: {
            /** @description Created room */
            readonly 201: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["Room"];
                };
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 409: components["responses"]["Conflict"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly getRoom: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Room state */
            readonly 200: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["Room"];
                };
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 404: components["responses"]["NotFound"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly deleteRoom: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Deleted */
            readonly 204: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content?: never;
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 404: components["responses"]["NotFound"];
            readonly 409: components["responses"]["Conflict"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly listActiveSessions: {
        readonly parameters: {
            readonly query?: {
                readonly cursor?: components["parameters"]["UuidCursor"];
                readonly limit?: components["parameters"]["Limit"];
            };
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Active sessions */
            readonly 200: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["SessionPage"];
                };
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 404: components["responses"]["NotFound"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly listRoomJoinRequests: {
        readonly parameters: {
            readonly query?: {
                readonly cursor?: components["parameters"]["UuidCursor"];
                readonly limit?: components["parameters"]["Limit"];
            };
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Pending requests, ordered oldest first */
            readonly 200: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["JoinRequestPage"];
                };
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 404: components["responses"]["NotFound"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly requestRoomAccess: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Join request */
            readonly 201: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["JoinRequest"];
                };
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 404: components["responses"]["NotFound"];
            readonly 409: components["responses"]["Conflict"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly cancelRoomAccessRequest: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Cancelled */
            readonly 204: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content?: never;
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 404: components["responses"]["NotFound"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly decideJoinRequest: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly requestId: components["parameters"]["RequestId"];
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly requestBody: {
            readonly content: {
                readonly "application/json": components["schemas"]["DecideJoinRequestRequest"];
            };
        };
        readonly responses: {
            /** @description Decided request */
            readonly 200: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["JoinRequest"];
                };
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 404: components["responses"]["NotFound"];
            readonly 409: components["responses"]["Conflict"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly removeRoomMember: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
                readonly userId: components["parameters"]["UserId"];
            };
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Removed */
            readonly 204: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content?: never;
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 404: components["responses"]["NotFound"];
            readonly 409: components["responses"]["Conflict"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly leaveRoom: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Left */
            readonly 204: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content?: never;
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 404: components["responses"]["NotFound"];
            readonly 409: components["responses"]["Conflict"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly listMessages: {
        readonly parameters: {
            readonly query?: {
                readonly cursor?: components["parameters"]["UuidCursor"];
                readonly limit?: components["parameters"]["Limit"];
            };
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Messages in chronological order within the requested newest-first page */
            readonly 200: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["MessagePage"];
                };
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 404: components["responses"]["NotFound"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly sendMessage: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly requestBody: {
            readonly content: {
                readonly "application/json": components["schemas"]["SendMessageRequest"];
            };
        };
        readonly responses: {
            /** @description Message */
            readonly 201: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["ChatMessage"];
                };
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 404: components["responses"]["NotFound"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly transferRoomOwnership: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly requestBody: {
            readonly content: {
                readonly "application/json": components["schemas"]["TransferOwnershipRequest"];
            };
        };
        readonly responses: {
            /** @description Updated room */
            readonly 200: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["Room"];
                };
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 404: components["responses"]["NotFound"];
            readonly 409: components["responses"]["Conflict"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly startSession: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly roomId: components["parameters"]["RoomId"];
            };
            readonly cookie?: never;
        };
        readonly requestBody?: never;
        readonly responses: {
            /** @description Session */
            readonly 201: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["StudySession"];
                };
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 404: components["responses"]["NotFound"];
            readonly 409: components["responses"]["Conflict"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
    readonly updateSession: {
        readonly parameters: {
            readonly query?: never;
            readonly header?: never;
            readonly path: {
                readonly sessionId: components["parameters"]["SessionId"];
            };
            readonly cookie?: never;
        };
        readonly requestBody: {
            readonly content: {
                readonly "application/json": components["schemas"]["UpdateSessionRequest"];
            };
        };
        readonly responses: {
            /** @description Session */
            readonly 200: {
                headers: {
                    readonly "x-request-id": components["headers"]["RequestId"];
                    readonly [name: string]: unknown;
                };
                content: {
                    readonly "application/json": components["schemas"]["StudySession"];
                };
            };
            readonly 400: components["responses"]["BadRequest"];
            readonly 401: components["responses"]["Unauthorized"];
            readonly 403: components["responses"]["Forbidden"];
            readonly 404: components["responses"]["NotFound"];
            readonly 409: components["responses"]["Conflict"];
            readonly 429: components["responses"]["TooManyRequests"];
            readonly 500: components["responses"]["InternalServerError"];
            readonly 503: components["responses"]["ServiceUnavailable"];
        };
    };
}

export const contractVersion = "0.4.0-beta.1" as const;
export const realtimeSchemaVersion = 1 as const;

export type AppIdWire = components["schemas"]["AppId"];
export type UserIdWire = components["schemas"]["UserId"];
export type PresenceStatusWire = components["schemas"]["PresenceStatus"];
export type RoomRoleWire = components["schemas"]["RoomRole"];
export type JoinRequestStatusWire = components["schemas"]["JoinRequestStatus"];
export type JoinRequestDecisionWire = components["schemas"]["JoinRequestDecision"];
export type SessionStatusWire = components["schemas"]["SessionStatus"];
export type ApplicationWire = components["schemas"]["Application"];
export type CreateApplicationRequestWire = components["schemas"]["CreateApplicationRequest"];
export type UpdateApplicationRequestWire = components["schemas"]["UpdateApplicationRequest"];
export type ApplicationPageWire = components["schemas"]["ApplicationPage"];
export type MemberWire = components["schemas"]["Member"];
export type RoomWire = components["schemas"]["Room"];
export type RoomPageWire = components["schemas"]["RoomPage"];
export type JoinRequestWire = components["schemas"]["JoinRequest"];
export type JoinRequestPageWire = components["schemas"]["JoinRequestPage"];
export type ChatMessageWire = components["schemas"]["ChatMessage"];
export type MessagePageWire = components["schemas"]["MessagePage"];
export type StudySessionWire = components["schemas"]["StudySession"];
export type SessionPageWire = components["schemas"]["SessionPage"];
export type CreateRoomRequestWire = components["schemas"]["CreateRoomRequest"];
export type DecideJoinRequestRequestWire = components["schemas"]["DecideJoinRequestRequest"];
export type TransferOwnershipRequestWire = components["schemas"]["TransferOwnershipRequest"];
export type SendMessageRequestWire = components["schemas"]["SendMessageRequest"];
export type UpdateSessionRequestWire = components["schemas"]["UpdateSessionRequest"];
export type ErrorResponseWire = components["schemas"]["ErrorResponse"];
export type LivenessResponseWire = components["schemas"]["LivenessResponse"];
export type ReadinessResponseWire = components["schemas"]["ReadinessResponse"];
export type MetricsResponseWire = components["schemas"]["MetricsResponse"];

export interface MembershipUpdatedPayloadWire {
  readonly roomId: string;
  readonly active: boolean;
}

export interface RealtimeEnvelopeBaseWire {
  readonly schemaVersion: typeof realtimeSchemaVersion;
  readonly eventId: string;
  readonly roomId: string | null;
  readonly roomVersion: number | null;
  readonly occurredAt: string;
}

export type RoomStateEventWire = Omit<RealtimeEnvelopeBaseWire, "roomId" | "roomVersion"> & {
  readonly type: "room.state";
  readonly roomId: string;
  readonly roomVersion: number;
  readonly payload: RoomWire;
};

export type MembershipUpdatedEventWire = Omit<RealtimeEnvelopeBaseWire, "roomId" | "roomVersion"> & {
  readonly type: "membership.updated";
  readonly roomId: string;
  readonly roomVersion: number;
  readonly payload: MembershipUpdatedPayloadWire;
};

export type JoinRequestCreatedEventWire = Omit<RealtimeEnvelopeBaseWire, "roomId" | "roomVersion"> & {
  readonly type: "join-request.created";
  readonly roomId: string;
  readonly roomVersion: null;
  readonly payload: JoinRequestWire;
};

export type JoinRequestUpdatedEventWire = Omit<RealtimeEnvelopeBaseWire, "roomId" | "roomVersion"> & {
  readonly type: "join-request.updated";
  readonly roomId: string;
  readonly roomVersion: null;
  readonly payload: JoinRequestWire;
};

export type MemberPresenceUpdatedEventWire = Omit<RealtimeEnvelopeBaseWire, "roomId" | "roomVersion"> & {
  readonly type: "member.presence.updated";
  readonly roomId: string;
  readonly roomVersion: number;
  readonly payload: MemberWire;
};

export type ChatMessageCreatedEventWire = Omit<RealtimeEnvelopeBaseWire, "roomId" | "roomVersion"> & {
  readonly type: "chat.message.created";
  readonly roomId: string;
  readonly roomVersion: null;
  readonly payload: ChatMessageWire;
};

export type SessionUpdatedEventWire = Omit<RealtimeEnvelopeBaseWire, "roomId" | "roomVersion"> & {
  readonly type: "session.updated";
  readonly roomId: string;
  readonly roomVersion: null;
  readonly payload: StudySessionWire;
};

export type RealtimeEnvelopeWire = RoomStateEventWire | MembershipUpdatedEventWire | JoinRequestCreatedEventWire | JoinRequestUpdatedEventWire | MemberPresenceUpdatedEventWire | ChatMessageCreatedEventWire | SessionUpdatedEventWire;

export function toRoomWire(value: RoomWire): RoomWire {
  return value;
}

export function toRealtimeEnvelopeWire(value: RealtimeEnvelopeWire): RealtimeEnvelopeWire {
  return value;
}
