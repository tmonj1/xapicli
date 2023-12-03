#
# Generate an API definition file from an OpenAPI spec file
#

# Supposed OpenAPI format (Example)
# 
# {
#   "paths": {
#     "/pet": {
#       "post": {
#         "parameters": [
#           {
#             "name": "status",
#             "in": "query",
#             "required": true,
#             "schema": {
#               "type": "string",
#               "enum": ["available", "pending", "sold"],
#               "default": "available"
#             }
#           }
#         ],
#         "requestBody": {
#           "required": true,
#           "content": {
#             "application/json": {
#               "schema": {
#                 "required": ["name", "photoUrls"],
#                 "properties": {
#                   "id": {
#                     "type": "integer",
#                     "format": "int64",
#                   },
#                   "name": {
#                     "type": "string",
#                   },
#                   "photoUrls": {
#                     "type": "array",
#                     "items": {"type": "string"}
#                   },
#                   "status": {
#                     "type": "string",
#                     "enum": ["available", "pending", "sold"]
#                   }
#                 },
#                 "type": "object"
#               }
#             }
#           }
#         }
#       }
#     }
#   }
# }

#
# Script
#

# extract elements under "paths"
.paths 
# split each resource to a single line in "key=resource-name, value=api-desc" format
| to_entries 
# convert each line into the {"resource-name": {api-desc}} format using `map`
| map({
    key,
    value: [
      .value 
      # split each HTTP method to a single line in "key=HTTP-method, value=api-desc" format
      | to_entries[] 
      # conver each line into the {"method":"HTTP-method", 
      # {query_parameters, post_parameters, post_parameters_required}} format
      | {
          method: .key,
          query_parameters: (
            [
              .value.parameters[]? 
              | select(.in == "query")
              | { name: .name, type: .schema.type, required: (.required // false) }
            ] // []
          ),
          post_parameters: (
            .value.requestBody.content["application/json"].schema.properties // []
            | [to_entries[] | {"name": .key} +  .value] 
          ),
          post_parameters_required: (
            .value.requestBody.content["application/json"].schema.required // {}
          )
        }
      | if .method == "post" or .method == "put" then 
          .post_parameters_required as $required_params 
          | .post_parameters
          |= map (
              . as $post_param
              | 
              if $required_params | any (. == $post_param.name) then
                $post_param + {required: true}
              else
                $post_param
              end
            )
        else
          del(.post_parameters)
        end
      | del(.post_parameters_required)
    ]
  }) 
| from_entries