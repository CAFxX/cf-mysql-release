# Configuration Options

## Configuring the Service Name and Deployment Name
In [cf-mysql v27](https://github.com/cloudfoundry/cf-mysql-release/releases/tag/v27) and later, you can control how the mysql service appears in the marketplace and the list of BOSH deployments. You can do this during manifest generation by overriding the properties `service_name` and `deployment_name` when creating your own customized version of the [property-overrides.yml](https://github.com/cloudfoundry/cf-mysql-release/blob/master/manifest-generation/examples/property-overrides.yml#L22) example.

After you've run both `bosh deploy` and `bosh run errand deregister-and-purge-instances`, the output of `cf marketplace` will look like:

- 
    ```sh
    $ cf marketplace
    Getting services from marketplace in org accept / space test as admin...
    OK
    
    service            plans        description
    myspecial-mysql   100mb, 1gb   MySQL databases on demand
    
    TIP:  Use 'cf marketplace -s SERVICE' to view descriptions of individual plans of a given service.
    ```

## Updating Service Plans

Updating the service instances is supported; see [Service plans and instances](docs/service-plans-instances.md) for details.

## Read-Only Administrator User

The manifest optionally allows the user to specify a password for the `roadmin` user. By supplying this password, the service will automatically create a user that has access to read all databases, but permission to write to none of them.

This parameter is defined in the [spec file](../jobs/mysql/spec#L84).

## Pre-seeding Databases

Normally databases are created via the `cf create-service` command, and
a MySQL user is created and given access to that database when an app is bound to that service instance.
However, it is sometimes useful to have databases and users already available when the service is deployed,
without having to run `cf create-service` or bind an app.
To specify any preseeded databases, add the following to the deployment manifest:

```
jobs:
- name: mysql_z1
  properties:
    seeded_databases:
    - name: db1
      username: user1
      password: pw1
    - name: db2
      username: user2
      password: pw2
```

Note 1: If a seeded database is renamed in the manifest, a new database will be created with the new name on the next deploy. The old one will not be deleted. If a username for a database is changed, a new user with the new username is created on the next deploy. We do not support changing the password for a user via the manifest, you will need to update it manually using SQL statements.

Note 2: If all you need is a database deployment, it is possible to deploy this
release with zero broker instances and completely remove any dependencies on Cloud Foundry.
See the [proxy](jobs/proxy/spec) and [acceptance-tests](jobs/acceptance-tests/spec) spec files for standalone configuration options.

## Setting wsrep_cluster_name

The current the version now allows `wsrep_cluster_name` to be set manually.

To set the name for a new cluster, update the `cf_mysql.mysql.cluster_name` property in the mysql instance group. Deploy and the cluster should come up with your new name.

To set the name for an existing cluster is a bit more moving parts and requires some down time. Steps are as follows:
 * Scale the cluster down to 1 node
 * Update the `cf_mysql.mysql.cluster_name` property in the mysql instance group
 * Scale the cluster back up to 3 nodes
